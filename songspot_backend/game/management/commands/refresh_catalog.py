"""
Keep the category pools stocked from Deezer.

Replaces the one-shot seeding commands. `seed_curated_artists` walked a fixed
list of 206 names and stopped; this runs on a schedule and pulls whatever
Deezer's editors currently list, so a category is never a frozen snapshot of
the day it was seeded and a long session can no longer drain it.

    python manage.py refresh_catalog                  # every category
    python manage.py refresh_catalog --category pop   # just one
    python manage.py refresh_catalog --stale-only     # only what has aged out
    python manage.py refresh_catalog --replace        # rebuild instead of add
    python manage.py refresh_catalog --dry-run        # report, change nothing

On a fresh database the first run also creates the category playlists, so
this one command is all a new install needs before it can play.

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

from game.models import (
    CATEGORY_CHOICES, Artist, CatalogSetting, Playlist, PlaylistTrack, Track,
)
from game.services import DeezerService
from game.services.deezer_http import BULK_MAX_WAIT, DeezerHttp
from game.services import cache_utils
from game.services.catalog import (
    is_playable_payload,
    purge_expired_claims,
    upsert_artist,
    upsert_track,
)

# Where each category refills from: Deezer editorial playlists, and nothing
# else.
#
# Several categories used to read genre charts. Deezer scopes a chart to the
# country of the requesting IP. There is no country parameter and no header
# that overrides it (both tested; `?country=US` is accepted and silently
# ignored), so a chart reflects wherever the machine running this happens to
# be. Read from a laptop in France, Hip-Hop was French rap top to bottom and
# Latin Pop had Collectif Métissé in it. Read from prod, which Deezer places in
# Finland (`/infos` answers FI), Pop filled up with Isac Elliot, Haloo
# Helsinki! and helmi marleena, Rock with Eppu Normaali and Apulanta, and Dance
# with Portion Boys, for an audience that mostly plays Bad Bunny and Drake.
# Editorial playlists return the same tracks from anywhere.
#
# Deezer's "Top <country>" playlists look like a way to choose the country and
# are not: Top South Korea opened with two German acts, six Yiruma tracks and
# Gracie Abrams. They are stale or mis-curated.
#
# Prefer an editor's evergreen sets (decade hits, essentials) over "new",
# "radar" and weekly playlists. A curated source skips the popularity floor, so
# nothing downstream catches a song nobody knows, and recent is not the same as
# well known. Where an editor publishes a decade set, take the whole set: a pool
# of only current songs is unplayable for half the room, and the point of a
# blind test is that someone recognises the song.
#
# Check who published a playlist before adding it. "Rock Super Hits" looks like
# the Rock editor's and is Deezer Deutschland's: Die Ärzte, Madsen, Die Toten
# Hosen.
SOURCES = {
    # Laeti, the Pop editor: a hits playlist for every decade since the 60s,
    # plus the all-time essentials and the recent-years rewind.
    'pop':        [620264073, 1470022445, 867825522, 878989033, 248297032,
                   14917741483, 13650084141, 1036183001, 4888783264],
    # Rod, the Rock editor: the essentials and a set per decade. Not his
    # "Rock Hits", which is this month's new rock.
    'rock':       [1306931615, 1437011185, 1405240385, 8621268482, 1728093421,
                   1419215845, 1057779131],
    # Laeti's Dance & EDM sets: current hits, the party classics, Eurodance and
    # one set per decade.
    'dance':      [706093725, 4613753548, 6237312204, 1251129741, 4135981802,
                   4135818362, 2159765062, 13651021241],
    # Ayoub, the R&B editor: the US canon from the 90s on. The French R&B
    # editor's sets are for a different audience.
    'rnb':        [1999466402, 1314725125, 1699545511, 5014738124, 2021626162,
                   5411628342],
    # French on purpose, so French editorial sets: Laeti's essentials and her
    # hits by decade.
    'variete_fr': [1420459465, 700895155, 788022051, 1189520191, 1051470831,
                   1162725851],
    # Not a chart. Genre 116 read from France is French rap top to bottom —
    # Mauvais djo, Timal, Leto, GIMS, PLK, Jul — which made this category an
    # exact duplicate of rap_fr. These are Deezer's US rap editorial
    # playlists, current plus three decades.
    'hiphop':     [1677006641, 7662551722, 4676818664, 1724212365],
    # Not genre 106: that chart is Kygo, Ofenbach, Clean Bandit and Martin
    # Garrix, which is the `dance` category, not this one. Electro here is the
    # genre with a history — Kraftwerk, Daft Punk, Massive Attack, Underworld —
    # which is the Electropolis set, the electronic editor's own. Avoid
    # "Electronic Hits": it is club booking, not blind-test material.
    #
    # The thinnest pool of the fourteen even so: roughly half of what these
    # return is rejected as a variant, because the editor's picks are full of
    # "(Radio Edit)" and "(2024 Remaster)".
    'electro':    [943229685, 834285741, 3801761042, 962293895],
    # Deezer's Latin editor does not separate latin pop from reggaeton —
    # every "Latin" playlist is half Bad Bunny — so neither do we.
    'latino':     [178699142, 1273315391, 11120289724, 5104249748, 2045665684],
    'afrobeats':  [3153080842, 10759580842, 1440614715, 1482254815],
    # Deezer has no Indian editor to take sets from, and genre 81 read from
    # prod returns six tracks.
    'bollywood':  [5714603022],
    'kpop':       [4096400722, 12244134951, 11012274682, 11012482922],
    'jpop':       [6049895724, 5206929684],
    # The Rapstars set, one playlist per decade, plus the current one. Not
    # `Actu Rap` (1071669561): that is the new-releases playlist, it rotates
    # weekly, and it is the sole reason Verso, Tchubi, Blaame, Swift Guad and
    # B.O Wunna were in the pool — none of the Rapstars playlists contained a
    # single one of them. Recency is not notoriety, and a curated source skips
    # the popularity floor, so nothing else was going to catch them. `Rapstars`
    # still brings recent rap in, picked on merit rather than release date.
    'rap_fr':     [9563400362, 5175061384, 4676814864, 1182010551, 3272614282],
    # Yannick, the Soul & Funk editor: disco, funk and the party sets.
    'disco':      [2015058202, 3798795702, 5505174422, 4699436964],
}

PAGE_SIZE = 100

# The most pages read from any one playlist. Editorial sets run 50 to 100
# tracks and a few reach 105. The cap exists so that a mistyped source ID
# pointing at someone's ten-thousand-track playlist cannot use up the night's
# Deezer quota.
MAX_PAGES = 5


class Command(BaseCommand):
    help = 'Refresh category pools from Deezer editorial playlists.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--category',
            help='Only refresh this category key (e.g. pop, rap_fr).',
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

        # Paced, not rushed: this job makes one call per artist on top of the
        # playlists, so it queues behind the rate limiter instead of giving up
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

        # Swept here because this is the daily catalogue job and a claim is
        # catalogue bookkeeping. Dropping an expired one changes no behaviour —
        # `_claim` hands it to the next caller anyway — but the cache they used
        # to live in expired them for free, and a table will not.
        if not dry_run:
            purged = purge_expired_claims()
            if purged:
                self.stdout.write(f'{purged} expired enrichment claims dropped')
            created = self._ensure_playlists(only)
            if created:
                self.stdout.write(f'Created the missing categories: {", ".join(created)}')

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
                deezer, playlist, sources, dry_run, options['replace'],
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
    def _ensure_playlists(only=None) -> list[str]:
        """
        Create any category playlist the database does not have yet.

        Prod has had its fourteen since they were seeded, but a fresh database
        only gets the two a migration creates. This command only fills
        playlists that exist, so a new install used to end up with no
        categories and nothing to play.
        """
        labels = dict(CATEGORY_CHOICES)
        created = []
        for category in SOURCES:
            if only and category != only:
                continue
            if not Playlist.objects.filter(category=category).exists():
                Playlist.objects.create(name=labels.get(category, category), category=category)
                created.append(category)
        return created

    @staticmethod
    def _shared_cache_reachable() -> bool:
        from django.core.cache import caches
        try:
            caches[cache_utils.CACHE_ALIAS].get('refresh_catalog_probe')
        except Exception:
            return False
        return True

    @staticmethod
    def _playlist_payloads(deezer, deezer_playlist_id) -> list:
        """
        Every track of one editorial playlist, however many pages it runs to.

        Only the first hundred used to be read, which silently dropped the end
        of any set longer than that.
        """
        payloads = []
        for page in range(MAX_PAGES):
            batch = deezer.get_playlist_tracks(
                deezer_playlist_id, limit=PAGE_SIZE, index=page * PAGE_SIZE,
            )
            payloads.extend(batch)
            if len(batch) < PAGE_SIZE:
                break
        return payloads

    def _refresh_one(self, deezer, playlist, sources, dry_run, replace=False) -> dict:
        counts = {'imported': 0, 'linked': 0, 'rejected': 0}
        payloads = []
        for deezer_playlist_id in sources:
            payloads.extend(self._playlist_payloads(deezer, deezer_playlist_id))

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
            # Everything this command reads comes from an editorial playlist,
            # so it carries that provenance into the catalogue.
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
        self._rank_songs(playlist)
        # Cleared rather than left over from the chart days: previews reads a
        # chart as an audio container, and one scoped to some other country
        # rarely holds the tracks this pool plays.
        playlist.deezer_genre_id = None
        playlist.deezer_playlist_ids = list(sources)
        playlist.refreshed_at = timezone.now()
        playlist.save(update_fields=[
            'deezer_genre_id', 'deezer_playlist_ids', 'refreshed_at',
        ])
        return counts

    @staticmethod
    def _rank_songs(playlist: Playlist) -> None:
        """
        Record how well known each song in the pool is, for the all-genre mix.

        A song's rank is the best among all of its releases in the catalogue,
        not the rank of the release the editor happened to list. Editorial
        playlists often point at a compilation or a remaster whose own rank is
        a small fraction of the original's, so ranking only the listed release
        would make a classic look obscure.
        """
        links = list(
            PlaylistTrack.objects.filter(playlist=playlist).select_related('track')
        )
        keys = {
            (link.track.norm_title, link.track.norm_artist)
            for link in links if link.track.norm_title
        }
        titles = sorted({title for title, _ in keys})
        best: dict[tuple[str, str], int] = {}
        for start in range(0, len(titles), 400):
            for title, artist, rank in (
                Track.objects
                .filter(norm_title__in=titles[start:start + 400])
                .values_list('norm_title', 'norm_artist', 'rank')
            ):
                if (title, artist) in keys and rank > best.get((title, artist), 0):
                    best[(title, artist)] = rank
        for link in links:
            key = (link.track.norm_title, link.track.norm_artist)
            link.song_rank = max(best.get(key, 0), link.track.rank or 0)
        PlaylistTrack.objects.bulk_update(links, ['song_rank'], batch_size=500)

    def _enrich_artists(self, deezer, tracks: list) -> None:
        """
        Fill in follower counts for the artists we just imported.

        Playlist payloads name the artist but never say how big they are, and
        that number is what keeps the guess list usable: it is what separates
        The Weeknd from the four unknown singers whose covers of "Blinding
        Lights" rank almost as highly. One extra call per artist is far too
        slow for autocomplete, but nothing at all for a nightly job — and the
        result is cached for a week afterwards.
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
