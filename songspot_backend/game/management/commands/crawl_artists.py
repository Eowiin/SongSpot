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

**Metadata only.** Preview URLs are signed with a fifteen-minute expiry, so
importing audio links in a nightly job would be importing dead data. Rounds
resolve their own audio at play time; see `game/services/previews.py`.

Resumable by construction: an artist whose `top_refreshed_at` is set is
skipped, so a run that dies halfway costs only the work in flight, and
tomorrow's run continues where this one stopped rather than starting over.
"""

import time
from collections import deque

from django.core.management.base import BaseCommand
from django.utils import timezone

from game.models import Artist, SearchMiss
from game.services import DeezerService
from game.services.catalog import upsert_artist, upsert_tracks
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
            '--dry-run', action='store_true',
            help='Report what would be crawled without writing or calling.',
        )

    def handle(self, *args, **options):
        budget = max(1, options['max_calls'])
        dry_run = options['dry_run']
        min_fans = options['min_fans']

        # Nobody is waiting on this, and giving up means a thinner catalogue,
        # so it queues behind the rate limiter rather than timing out the way a
        # web request does.
        deezer = DeezerService(http=DeezerHttp(max_wait=BULK_MAX_WAIT))

        seeds = self._seeds(deezer, options.get('seeds_only'), dry_run)
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
        started = time.monotonic()

        while queue and calls < budget:
            artist_id = queue.popleft()

            artist = Artist.objects.filter(deezer_id=artist_id).first()
            if artist is None or not artist.name:
                payload = deezer.get_artist(artist_id)
                calls += 1
                if not payload:
                    continue
                artist = upsert_artist(payload)
                if artist is None:
                    continue

            if artist.is_blocked or artist.is_junk:
                continue

            # Already stocked by an earlier run or by a player's session.
            if artist.top_refreshed_at is None:
                payloads = deezer.get_artist_top_tracks(artist_id, limit=TOP_TRACKS)
                calls += 1
                for payload in payloads:
                    payload.setdefault('artist', {}).setdefault('id', artist_id)
                tracks = upsert_tracks(payloads)
                imported_tracks += len(tracks)
                imported_artists += 1
                artist.top_refreshed_at = timezone.now()
                artist.save(update_fields=['top_refreshed_at'])

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
        self.stdout.write(self.style.SUCCESS(
            f'Crawled {imported_artists} artists / {imported_tracks} tracks '
            f'in {calls} calls ({elapsed:.0f}s). {len(queue)} left in the frontier.'
        ))

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
