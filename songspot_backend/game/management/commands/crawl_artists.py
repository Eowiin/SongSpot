"""
Grow the catalogue along Deezer's own artist graph.

`refresh_catalog` keeps the fourteen categories stocked from charts and
editorial playlists. That covers what is popular; it does not cover what a
given player is about to search for, and the gap between the two is what store
reviews are made of — "my artist isn't on here" is the single most common
complaint an app like this gets, and it is unanswerable while the catalogue is
a list of chart acts.

Searching for the missing artists by name is circular: we would have to know
their names first. So this walks outward instead. `/artist/{id}/related`
returns twenty adjacent artists per call, which makes a breadth-first search
from a few hundred seeds the cheapest way to reach the long tail — two calls
per artist discovered (one for their neighbours, one for their top tracks),
against a rate limit that allows eight a second.

    python manage.py crawl_artists                      # a night's budget
    python manage.py crawl_artists --max-calls 2000     # a smaller bite
    python manage.py crawl_artists --seeds-only misses  # just what players asked for
    python manage.py crawl_artists --dry-run
    python manage.py crawl_artists --floor-report --max-calls 200   # what a run would keep

**Metadata only.** Preview URLs are signed with a fifteen-minute expiry, so
importing audio links in a nightly job would be importing dead data. Rounds
resolve their own audio at play time; see `game/services/previews.py`.

Resumable by construction: an artist whose `top_refreshed_at` is set is
skipped, so a run that dies halfway costs only the work in flight, and
tomorrow's run continues where this one stopped rather than starting over.
"""

import time
from collections import Counter, deque

from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone

from game.models import Artist, SearchMiss
from game.services import DeezerService
from game.services.catalog import (
    payload_rejection,
    settings_row,
    upsert_artist,
    upsert_tracks,
)
from game.services.deezer_http import BULK_MAX_WAIT, DeezerHttp

# Calls a run will make before stopping. At the paced eight per second this is
# roughly forty minutes, which fits comfortably in the small hours alongside
# refresh_catalog.
DEFAULT_MAX_CALLS = 20_000

# Top tracks imported per artist. Fifty is more than any session will play and
# well past the point where a further page adds anything a player would
# recognise.
TOP_TRACKS = 50

# Neighbours are only followed from artists with at least this many followers.
# Without a floor the walk drifts into the very long tail — cover bands,
# uploads, bootlegs — and spends its budget there. This bounds the drift
# without blocking niche artists, which are still imported when a *player*
# names one: search enrichment applies no floor at all.
MIN_FANS_TO_EXPAND = 5_000


class Command(BaseCommand):
    help = "Crawl Deezer's artist graph to widen catalogue coverage."

    def add_arguments(self, parser):
        parser.add_argument(
            '--max-calls', type=int, default=DEFAULT_MAX_CALLS,
            help=f'Deezer requests to spend on this run (default: {DEFAULT_MAX_CALLS}).',
        )
        parser.add_argument(
            '--seeds-only', choices=['misses', 'charts'],
            help='Restrict the starting points to one source.',
        )
        parser.add_argument(
            '--min-fans', type=int, default=MIN_FANS_TO_EXPAND,
            help='Follower floor for following an artist\'s neighbours.',
        )
        parser.add_argument(
            '--track-min-fans', type=int, default=None,
            help=(
                "Follower floor for importing an artist's tracks. Defaults to "
                'the catalogue\'s own min_artist_fans, so the crawl stores what '
                'the game can actually serve. 0 imports from everyone.'
            ),
        )
        parser.add_argument(
            '--dry-run', action='store_true',
            help='Report what would be crawled without writing or calling.',
        )
        parser.add_argument(
            '--floor-report', action='store_true',
            help=(
                'Walk and fetch exactly as a real run would, write nothing, and '
                'report how much of the haul the quality floor would keep.'
            ),
        )

    def handle(self, *args, **options):
        budget = max(1, options['max_calls'])
        dry_run = options['dry_run']
        report = options['floor_report']
        min_fans = options['min_fans']
        # One floor, read from the catalogue settings, so tightening the game's
        # standard tightens what the crawl bothers to store rather than leaving
        # the two to drift apart.
        track_min_fans = options['track_min_fans']
        if track_min_fans is None:
            track_min_fans = settings_row().min_artist_fans

        if dry_run and report:
            raise CommandError(
                '--dry-run makes no calls, so there is no haul for --floor-report '
                'to judge. Pick one.'
            )
        # Both modes are read-only, and both must leave SearchMiss unmarked: a
        # miss struck off by a report is a gap the next *real* run would skip.
        read_only = dry_run or report

        # Nobody is waiting on this, and giving up means a thinner catalogue,
        # so it queues behind the rate limiter rather than timing out the way a
        # web request does.
        deezer = DeezerService(http=DeezerHttp(max_wait=BULK_MAX_WAIT))

        seeds = self._seeds(deezer, options.get('seeds_only'), read_only)
        if not seeds:
            self.stdout.write(self.style.WARNING('No seeds — nothing to crawl.'))
            return

        self.stdout.write(f'{len(seeds)} seeds, budget {budget} calls')
        if dry_run:
            for artist_id, label in list(seeds.items())[:20]:
                self.stdout.write(f'  would crawl {label} ({artist_id})')
            self.stdout.write(self.style.SUCCESS(f'Dry run: {len(seeds)} seeds.'))
            return

        queue = deque(seeds)
        # Everything queued or done. Membership is checked far more often than
        # it is added, and the walk revisits constantly — most of an artist's
        # neighbours are already known — so this set is what keeps the crawl
        # from going in circles.
        known = set(seeds)
        calls = 0
        imported_artists = 0
        imported_tracks = 0
        skipped_artists = 0
        verdicts: Counter[str] = Counter()
        started = time.monotonic()

        while queue and calls < budget:
            artist_id = queue.popleft()

            artist = Artist.objects.filter(deezer_id=artist_id).first()
            if artist is None or not artist.name:
                payload = deezer.get_artist(artist_id)
                calls += 1
                if not payload:
                    continue
                # A report must not leave the artist behind either, so it holds
                # the row in memory instead. The floor reads `nb_fan` off it,
                # which is the whole reason the artist is fetched before the
                # tracks are judged.
                artist = _transient_artist(payload) if report else upsert_artist(payload)
                if artist is None:
                    continue

            if artist.is_blocked or artist.is_junk:
                continue

            # An artist below the floor is still worth *having* — the row is
            # what makes them findable, and it is the search box, not the track
            # table, that answers "you don't have my artist". Their tracks are
            # not worth storing: none of them can pass `playable`, so a random
            # round can never serve one, and a player who names the artist gets
            # the whole discography on demand from `ensure_artist_tracks`.
            #
            # This is where the catalogue was growing without bound. The walk
            # already refused to *follow* artists under MIN_FANS_TO_EXPAND, but
            # imported fifty tracks from each one before turning back: 1.23M of
            # the first 1.5M rows came from artists under this floor, and none
            # of them were ever playable.
            #
            # nb_fan of 0 reads as unknown, not tiny — the same convention rank
            # follows — so an artist we have no follower count for is imported.
            #
            # Only the tracks are skipped. Expansion is a separate decision
            # with its own floor below: an artist too small to stock can still
            # be the bridge to a big one, and cutting the walk here would
            # narrow the crawl instead of just trimming what it writes.
            if artist.nb_fan and artist.nb_fan < track_min_fans:
                skipped_artists += 1

            # Already stocked by an earlier run or by a player's session.
            elif artist.top_refreshed_at is None:
                payloads = deezer.get_artist_top_tracks(artist_id, limit=TOP_TRACKS)
                calls += 1
                for payload in payloads:
                    payload.setdefault('artist', {}).setdefault('id', artist_id)
                if report:
                    verdicts.update(self._judge(deezer, payloads, artist))
                    imported_tracks += len(payloads)
                else:
                    tracks = upsert_tracks(payloads)
                    imported_tracks += len(tracks)
                    artist.top_refreshed_at = timezone.now()
                    artist.save(update_fields=['top_refreshed_at'])
                imported_artists += 1

            if artist.nb_fan < min_fans or calls >= budget:
                continue

            for neighbour in deezer.get_related_artists(artist_id):
                nid = neighbour.get('id')
                if nid and nid not in known:
                    known.add(nid)
                    queue.append(nid)
            calls += 1

            if imported_artists and imported_artists % 100 == 0:
                self.stdout.write(
                    f'  {imported_artists} artists, {imported_tracks} tracks, '
                    f'{calls} calls, {len(queue)} queued'
                )

        elapsed = time.monotonic() - started

        if report:
            self._print_report(
                verdicts, imported_artists, calls, elapsed, len(queue),
                skipped_artists, track_min_fans,
            )
            return

        self.stdout.write(self.style.SUCCESS(
            f'Crawled {imported_artists} artists / {imported_tracks} tracks '
            f'in {calls} calls ({elapsed:.0f}s). {skipped_artists} artists under '
            f'the {track_min_fans}-fan floor kept their row but not their tracks. '
            f'{len(queue)} left in the frontier.'
        ))

    def _judge(self, deezer, payloads: list[dict], artist: Artist) -> list[str]:
        """
        The floor's verdict on each track of one artist's haul, as reason slugs.

        `directed=False` because this is the crawl: nobody asked for these
        tracks by name, which is exactly the case the popularity floor is there
        to judge. A player who names the artist gets them regardless, through
        `ensure_artist_tracks`.
        """
        return [
            payload_rejection(
                deezer.extract_track_info(payload), artist, directed=False,
            ) or 'kept'
            for payload in payloads
        ]

    def _print_report(self, verdicts, artists, calls, elapsed, frontier,
                      skipped, track_min_fans):
        total = sum(verdicts.values())
        if not total:
            self.stdout.write(self.style.WARNING(
                f'Nothing fetched in {calls} calls — no haul to judge.'
            ))
            return

        kept = verdicts.get('kept', 0)
        self.stdout.write('')
        self.stdout.write(
            f'{artists} artists, {total} tracks fetched, {calls} calls ({elapsed:.0f}s)'
        )
        self.stdout.write(
            f'{skipped} artists under the {track_min_fans}-fan floor were not fetched at all'
        )
        self.stdout.write('')
        for reason, count in verdicts.most_common():
            label = 'KEPT' if reason == 'kept' else f'rejected: {reason}'
            self.stdout.write(f'  {count:7d}  {100 * count / total:5.1f}%  {label}')
        self.stdout.write('')
        self.stdout.write(self.style.SUCCESS(
            f'The floor would store {kept} of {total} tracks '
            f'({100 * kept / total:.1f}%), leaving {frontier} in the frontier.'
        ))
        self.stdout.write(
            'Nothing was written. Rejected tracks stay reachable: a player who '
            'names the artist still gets them, fetched on demand.'
        )


    def _seeds(self, deezer: DeezerService, only: str | None, dry_run: bool) -> dict:
        """
        Where the walk starts, most valuable first.

        Player misses come first and are worth more than any chart: a recorded
        miss is a player who searched for something and got nothing, which is
        the most direct evidence of a gap the catalogue has.
        """
        seeds: dict[int, str] = {}

        if only != 'charts':
            pending = SearchMiss.objects.filter(crawled_at__isnull=True).order_by('-hits')[:200]
            for miss in pending:
                for payload in deezer.search_artists(miss.query, limit=3):
                    if payload.get('id'):
                        seeds.setdefault(payload['id'], payload.get('name', '?'))
                if not dry_run:
                    SearchMiss.objects.filter(pk=miss.pk).update(crawled_at=timezone.now())

        if only != 'misses':
            for payload in deezer.get_top_artists(limit=100):
                if payload.get('id'):
                    seeds.setdefault(payload['id'], payload.get('name', '?'))
            # Everything we already hold with a follower count is a legitimate
            # starting point too, and costs nothing to enumerate.
            for artist in Artist.objects.filter(
                is_blocked=False, top_refreshed_at__isnull=True,
            ).order_by('-nb_fan')[:200]:
                seeds.setdefault(artist.deezer_id, artist.name)

        return seeds


def _transient_artist(payload: dict) -> Artist | None:
    """
    An unsaved Artist carrying what the floor reads, for report runs.

    Mirrors `upsert_artist`'s guard so a report skips exactly the payloads a
    real run would skip — otherwise the report would judge tracks belonging to
    artists the crawl never actually keeps.
    """
    deezer_id = payload.get('id')
    name = (payload.get('name') or '').strip()
    if not deezer_id or not name:
        return None
    return Artist(deezer_id=deezer_id, name=name, nb_fan=payload.get('nb_fan') or 0)
