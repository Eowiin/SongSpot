"""
Keep the category pools stocked from Deezer.

Replaces the one-shot seeding commands. `seed_curated_artists` walked a fixed
list of 206 names and stopped; this runs on a schedule and pulls whatever is
currently charting, so a category is never a frozen snapshot of the day it was
seeded and a long session can no longer drain it.

    python manage.py refresh_catalog                  # every category
    python manage.py refresh_catalog --category pop   # just one
    python manage.py refresh_catalog --stale-only     # only what has aged out
    python manage.py refresh_catalog --replace        # rebuild instead of add
    python manage.py refresh_catalog --dry-run        # report, change nothing

It is deliberately the only place that writes PlaylistTrack in bulk: the play
endpoint reads those rows and never calls Deezer itself, which is what keeps a
live round off the network.

Two schedules, because a run without `--replace` has no eviction at all:

* nightly `--stale-only`, which only ever adds, so new releases arrive;
* weekly `--replace`, which rebuilds each pool from its current sources.

The weekly one is not optional. Without it a pool is a permanent accumulation
of everything ever imported into it, including rows from sources that have
since been retired — which is how nine Linkin Park tracks came to sit in Rap
Français, and Collectif Métissé in Latin Pop.
"""

from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from game.models import Artist, CatalogSetting, Playlist, PlaylistTrack
from game.services import DeezerService
from game.services.deezer_http import BULK_MAX_WAIT, DeezerHttp
from game.services import cache_utils
from game.services.catalog import is_playable_payload, upsert_artist, upsert_track

# Where each category refills from.
#
# The choice between a genre chart and an editorial playlist is not cosmetic.
# Deezer's charts are scoped to the *requesting IP's* country — there is no
# country parameter and no header that overrides it (both tested; they are
# silently ignored), so a server in France gets French charts, permanently.
# Editorial playlists are curated per genre and carry no such bias.
#
# That makes charts the right source wherever a French audience is the point,
# and the wrong one wherever the genre lives somewhere else. Genre 2, "Musique
# africaine", read from France returns French-African pop: Aya Nakamura at the
# top, with Shakira and Jungeli behind her. Accurate for France, and not
# Afrobeats. The playlists below give Burna Boy, WizKid, Rema, Ayra Starr.
#
# Deezer's "Top <country>" playlists look like the obvious answer and are not:
# Top South Korea currently opens with two German acts, six Yiruma tracks and
# Gracie Abrams. They are stale or mis-curated.
#
# Genres with no chart of their own also use playlists — Deezer files K-pop and
# J-pop under "Musique asiatique" and French rap under "Chanson française",
# both far too broad to play from.
#
# There is no country parameter to reach for as an escape hatch: `?country=US`
# on a chart is accepted and silently ignored. Editorial playlists are the only
# way out of the France scoping, so any category whose centre of gravity is not
# France is sourced from them.
#
# Where a genre has an editorial set split by decade, take the whole set rather
# than the one "hits" playlist. A pool made only of what is charting now is
# unplayable for half the room — the point of a blind test is that someone
# recognises the song.
SOURCES = {
    # French-market charts, which is the intended audience for these.
    'rnb':        {'genre': 165},
    'variete_fr': {'genre': 52},
    # Mixes: keep the French chart, which is where a French audience's own
    # references live — Téléphone and Indochine belong in Rock — and add the
    # editorial decade sets, which is the half a chart structurally cannot
    # give. A chart only ever knows about now.
    'pop':        {'genre': 132,
                   'playlists': [4888783264, 8326097522, 1964085082]},
    'rock':       {'genre': 152,
                   'playlists': [1306931615, 1405240385, 8621268482, 1728093421]},
    'dance':      {'genre': 113,
                   'playlists': [706093725, 4135981802, 4135818362, 2159765062]},
    # Not a chart. Genre 116 read from France is French rap top to bottom —
    # Mauvais djo, Timal, Leto, GIMS, PLK, Jul — which made this category an
    # exact duplicate of rap_fr. These are Deezer's US rap editorial
    # playlists, current plus three decades.
    'hiphop':     {'playlists': [1677006641, 7662551722, 4676818664, 1724212365]},
    # Not genre 106: that chart is Kygo, Ofenbach, Clean Bandit and Martin
    # Garrix, which is the `dance` category, not this one. Electro here is the
    # genre with a history — Kraftwerk, Daft Punk, Massive Attack, Underworld —
    # which is the Electropolis set, the electronic editor's own. Avoid
    # "Electronic Hits": it is club booking, not blind-test material.
    #
    # The thinnest pool of the fourteen even so: roughly half of what these
    # return is rejected as a variant, because the editor's picks are full of
    # "(Radio Edit)" and "(2024 Remaster)".
    'electro':    {'playlists': [943229685, 834285741, 3801761042, 962293895]},
    # Genre 197 read from France is "Latino as sold in France": its tail is
    # Collectif Métissé, Slaï, DJ Steri and, at position 80, Future feat.
    # Drake. Deezer's Latin editor does not separate latin pop from reggaeton
    # either — every "Latin" playlist is half Bad Bunny — so neither do we.
    'latino':     {'playlists': [178699142, 1273315391, 11120289724,
                                 5104249748, 2045665684]},
    # Genre-curated, to escape the scoping.
    'afrobeats':  {'playlists': [3153080842, 10759580842, 1440614715, 1482254815]},
    'bollywood':  {'genre': 81, 'playlists': [5714603022]},
    'kpop':       {'playlists': [4096400722, 12244134951, 11012274682, 11012482922]},
    'jpop':       {'playlists': [6049895724, 5206929684]},
    # The Rapstars set, one playlist per decade, plus the current one. Not
    # `Actu Rap` (1071669561): that is the new-releases playlist, it rotates
    # weekly, and it is the sole reason Verso, Tchubi, Blaame, Swift Guad and
    # B.O Wunna were in the pool — none of the Rapstars playlists contained a
    # single one of them. Recency is not notoriety, and a curated source skips
    # the popularity floor, so nothing else was going to catch them. `Rapstars`
    # still brings recent rap in, picked on merit rather than release date.
    'rap_fr':     {'playlists': [9563400362, 5175061384, 4676814864,
                                 1182010551, 3272614282]},
    # Deezer has no disco/funk genre chart at all — the closest is 169
    # "Soul & Funk", which rnb already overlaps.
    'disco':      {'playlists': [2015058202, 3798795702, 5505174422, 4699436964]},
}

PAGE_SIZE = 100


class Command(BaseCommand):
    help = 'Refresh category pools from Deezer charts and editorial playlists.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--category',
            help='Only refresh this category key (e.g. pop, rap_fr).',
        )
        parser.add_argument(
            '--pages', type=int, default=3,
            help='Pages of %d tracks to pull per genre chart (default: 3).' % PAGE_SIZE,
        )
        parser.add_argument(
            '--stale-only', action='store_true',
            help='Skip categories refreshed within the configured TTL.',
        )
        parser.add_argument(
            '--replace', action='store_true',
            help=(
                'Rebuild the pool from the current sources instead of adding to '
                'it. Use after changing a category\'s SOURCES mapping — normal '
                'runs only ever add, so entries from a retired source would '
                'otherwise stay forever.'
            ),
        )
        parser.add_argument(
            '--dry-run', action='store_true',
            help='Report what would be imported without writing.',
        )

    def handle(self, *args, **options):
        config = CatalogSetting.get_solo()
        only = options.get('category')
        dry_run = options['dry_run']
        stale_only = options['stale_only']
        pages = max(1, options['pages'])

        # Paced, not rushed: this job makes one call per artist on top of the
        # charts, so it queues behind the rate limiter instead of giving up
        # after two seconds the way a web request does.
        deezer = DeezerService(http=DeezerHttp(max_wait=BULK_MAX_WAIT))

        # Say so up front. A missing shared cache is survivable but it changes
        # what this run costs — every response is re-fetched, and the rate
        # limiter paces this process alone rather than the whole fleet. Worth
        # knowing before reading a slow run as a Deezer problem.
        if cache_utils.is_degraded() or not self._shared_cache_reachable():
            self.stdout.write(self.style.WARNING(
                'Shared cache unreachable — running on the in-process fallback. '
                'Slower, and heavier on the Deezer quota. Check CACHE_REDIS_URL '
                '(or comment CHANNEL_LAYERS_REDIS_URL out for a local run).'
            ))

        cutoff = timezone.now() - timezone.timedelta(hours=config.playlist_ttl_hours)

        totals = {'imported': 0, 'linked': 0, 'rejected': 0}

        for playlist in Playlist.objects.all().order_by('name'):
            sources = SOURCES.get(playlist.category or '')
            if not sources:
                self.stdout.write(f'— {playlist.name}: no Deezer source mapped, skipping')
                continue
            if only and playlist.category != only:
                continue
            if stale_only and playlist.refreshed_at and playlist.refreshed_at > cutoff:
                self.stdout.write(f'— {playlist.name}: still fresh, skipping')
                continue

            self.stdout.write(self.style.WARNING(f'▸ {playlist.name}'))
            counts = self._refresh_one(
                deezer, playlist, sources, pages, dry_run, options['replace'],
            )
            for key in totals:
                totals[key] += counts[key]
            self.stdout.write(self.style.SUCCESS(
                f'  {counts["imported"]} imported, {counts["linked"]} linked, '
                f'{counts["rejected"]} rejected'
            ))

        self.stdout.write(self.style.SUCCESS(
            f'\nDone — {totals["imported"]} tracks imported, '
            f'{totals["linked"]} playlist entries, {totals["rejected"]} rejected.'
        ))

    @staticmethod
    def _shared_cache_reachable() -> bool:
        from django.core.cache import caches
        try:
            caches[cache_utils.CACHE_ALIAS].get('refresh_catalog_probe')
        except Exception:
            return False
        return True

    def _refresh_one(self, deezer, playlist, sources, pages, dry_run, replace=False) -> dict:
        counts = {'imported': 0, 'linked': 0, 'rejected': 0}
        payloads = []

        genre_id = sources.get('genre')
        if genre_id:
            for page in range(pages):
                batch = deezer.get_genre_chart_tracks(
                    genre_id, limit=PAGE_SIZE, index=page * PAGE_SIZE,
                )
                if not batch:
                    break
                payloads.extend(batch)

        for deezer_playlist_id in sources.get('playlists', []):
            payloads.extend(
                deezer.get_playlist_tracks(deezer_playlist_id, limit=PAGE_SIZE)
            )

        if not payloads:
            # Be careful what this blames. The first version of this command
            # exhausted the Deezer quota by itself and then reported every
            # remaining category as "Deezer unreachable", which sent the reader
            # looking for a network fault that did not exist.
            self.stdout.write(self.style.ERROR(
                '  no tracks returned — Deezer refused or returned nothing '
                '(rate limit, or a source ID that no longer exists); '
                'pool left as is'
            ))
            return counts

        tracks = []
        seen_deezer_ids = set()
        for payload in payloads:
            if payload.get('id') in seen_deezer_ids:
                continue
            seen_deezer_ids.add(payload.get('id'))

            info = deezer.extract_track_info(payload)
            # Everything this command reads comes from a chart or an editorial
            # playlist, so it carries that provenance into the catalogue.
            info['is_curated'] = True
            # A category pick is undirected — the game chooses, so the quality
            # floor applies. This is the one place it is enforced at import
            # time rather than at read time, to keep the junk out of the table
            # entirely rather than filtering it on every round.
            artist = None
            if not dry_run and info.get('deezer_artist_id'):
                artist = upsert_artist(payload.get('artist') or {})
            if not is_playable_payload(info, artist, directed=False, curated=True):
                counts['rejected'] += 1
                continue

            if dry_run:
                counts['imported'] += 1
                continue

            track = upsert_track(info)
            if track is None:
                counts['rejected'] += 1
                continue
            counts['imported'] += 1
            tracks.append(track)

        if dry_run:
            return counts

        self._enrich_artists(deezer, tracks)
        counts['linked'] = self._link(playlist, tracks, replace=replace)
        playlist.deezer_genre_id = genre_id
        playlist.deezer_playlist_ids = sources.get('playlists', [])
        playlist.refreshed_at = timezone.now()
        playlist.save(update_fields=[
            'deezer_genre_id', 'deezer_playlist_ids', 'refreshed_at',
        ])
        return counts

    def _enrich_artists(self, deezer, tracks: list) -> None:
        """
        Fill in follower counts for the artists we just imported.

        Chart and playlist payloads name the artist but never say how big they
        are, and that number is what keeps the guess list usable: it is what
        separates The Weeknd from the four unknown singers whose covers of
        "Blinding Lights" rank almost as highly. One extra call per artist is
        far too slow for autocomplete, but nothing at all for a nightly job —
        and the result is cached for a week afterwards.
        """
        ids = {t.deezer_artist_id for t in tracks if t.deezer_artist_id}
        if not ids:
            return

        unknown = list(
            Artist.objects.filter(deezer_id__in=ids, nb_fan=0)
            .values_list('deezer_id', flat=True)
        )
        # Artists we have never seen at all still need a row.
        unknown += [i for i in ids if not Artist.objects.filter(deezer_id=i).exists()]

        for artist_id in dict.fromkeys(unknown):
            payload = deezer.get_artist(artist_id)
            if payload:
                upsert_artist(payload)

    @transaction.atomic
    def _link(self, playlist: Playlist, tracks: list, replace: bool = False) -> int:
        """
        Attach the imported tracks to the category, highest ranking first.

        Existing entries are kept rather than replaced: a pool that only ever
        grows means a player's session never runs into a song being pulled out
        from under them, and old entries stay valid answers either way.

        `replace` is the exception, for when a category's sources change. Only
        the *links* go — the tracks themselves stay in the catalogue, still
        searchable and still valid answers; they simply stop being offered
        under this category.
        """
        if replace:
            PlaylistTrack.objects.filter(playlist=playlist).delete()

        existing = set(
            PlaylistTrack.objects
            .filter(playlist=playlist)
            .values_list('track_id', flat=True)
        )
        start = PlaylistTrack.objects.filter(playlist=playlist).count()
        new_entries = [
            PlaylistTrack(
                playlist=playlist,
                track=track,
                order_in_playlist=start + offset,
            )
            for offset, track in enumerate(
                sorted(
                    (t for t in tracks if t.id not in existing),
                    key=lambda t: -t.rank,
                )
            )
        ]
        PlaylistTrack.objects.bulk_create(new_entries, ignore_conflicts=True)
        return len(new_entries)
