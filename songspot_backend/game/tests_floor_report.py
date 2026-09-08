"""
`crawl_artists --floor-report` has one job and one hard constraint: report what
the floor would keep, and write nothing while doing it. The constraint is the
part worth a test — a report that quietly marked SearchMiss rows as crawled
would make the next real run skip exactly the gaps a player asked for.
"""

import contextlib
import io
from unittest.mock import patch

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase

from game.models import Artist, SearchMiss, Track

ARTIST = {'id': 900, 'name': 'Famous Act', 'nb_fan': 2_000_000}


def _track(deezer_id: int, *, rank: int, title: str = 'Song') -> dict:
    return {
        'id': deezer_id,
        'title': f'{title} {deezer_id}',
        'preview': f'https://example.com/{deezer_id}.mp3',
        'rank': rank,
        'artist': {'id': ARTIST['id'], 'name': ARTIST['name']},
    }


@contextlib.contextmanager
def _crawl(payloads: list[dict], artist: dict = ARTIST):
    """Run the crawler against a one-artist Deezer, capturing its output."""
    out = io.StringIO()
    with patch('game.services.DeezerService.search_artists', return_value=[artist]), \
         patch('game.services.DeezerService.get_top_artists', return_value=[]), \
         patch('game.services.DeezerService.get_artist', return_value=artist), \
         patch('game.services.DeezerService.get_artist_top_tracks', return_value=payloads), \
         patch('game.services.DeezerService.get_related_artists', return_value=[]), \
         contextlib.redirect_stdout(out):
        yield out


class FloorReportTests(TestCase):
    def setUp(self):
        SearchMiss.objects.create(query='famous act', norm_query='famous act', hits=9)

    def test_writes_nothing(self):
        with _crawl([_track(1, rank=900_000), _track(2, rank=10)]):
            call_command('crawl_artists', floor_report=True, seeds_only='misses')

        self.assertEqual(Track.objects.count(), 0)
        self.assertEqual(Artist.objects.count(), 0)
        # The miss must stay uncrawled, or the next real run skips this gap.
        self.assertIsNone(SearchMiss.objects.get().crawled_at)

    def test_separates_kept_from_rejected(self):
        payloads = [
            _track(1, rank=900_000),
            _track(2, rank=900_000),
            _track(3, rank=10),                          # under the rank floor
            _track(4, rank=900_000, title='Song (Live)'),  # a variant
        ]
        with _crawl(payloads) as out:
            call_command('crawl_artists', floor_report=True, seeds_only='misses')

        report = out.getvalue()
        self.assertIn('rank-below-floor', report)
        self.assertIn('variant', report)
        self.assertIn('would store 2 of 4 tracks', report)

    def test_below_floor_artist_keeps_its_row_but_not_its_tracks(self):
        # The row is what answers "you don't have my artist". The tracks are
        # what nothing can ever play, so they are not worth the write.
        obscure = {'id': 901, 'name': 'Small Act', 'nb_fan': 12}
        with _crawl([_track(1, rank=900_000)], artist=obscure):
            call_command('crawl_artists', seeds_only='misses')

        self.assertEqual(Artist.objects.filter(deezer_id=901).count(), 1)
        self.assertEqual(Track.objects.count(), 0)

    def test_the_floor_trims_tracks_without_narrowing_the_walk(self):
        # Between the two floors: too small to stock, big enough to still be a
        # bridge to someone larger. Cutting the walk here would shrink the
        # crawl's reach rather than just trimming what it writes.
        bridge = {'id': 902, 'name': 'Bridge Act', 'nb_fan': 10_000}
        neighbour = {'id': 903, 'name': 'Big Act', 'nb_fan': 5_000_000}
        with _crawl([_track(1, rank=900_000)], artist=bridge) as out, \
             patch('game.services.DeezerService.get_related_artists',
                   return_value=[neighbour]):
            call_command('crawl_artists', seeds_only='misses', max_calls=2)

        self.assertEqual(Track.objects.count(), 0)
        # The neighbour was reached, which is what proves expansion survived.
        self.assertIn('left in the frontier', out.getvalue())
        self.assertNotIn('0 left in the frontier', out.getvalue())

    def test_an_override_can_still_import_everything(self):
        obscure = {'id': 901, 'name': 'Small Act', 'nb_fan': 12}
        with _crawl([_track(1, rank=900_000)], artist=obscure):
            call_command('crawl_artists', seeds_only='misses', track_min_fans=0)

        self.assertEqual(Track.objects.count(), 1)

    def test_a_real_run_still_writes(self):
        with _crawl([_track(1, rank=900_000)]):
            call_command('crawl_artists', seeds_only='misses')

        self.assertEqual(Track.objects.count(), 1)
        self.assertIsNotNone(SearchMiss.objects.get().crawled_at)

    def test_dry_run_and_floor_report_are_exclusive(self):
        with self.assertRaises(CommandError):
            call_command('crawl_artists', dry_run=True, floor_report=True)


class PayloadRejectionTests(TestCase):
    """
    The fan floor is unreachable from the crawl now that it skips those
    artists outright, but it still judges the search-enrichment path — so the
    reason has to keep working, and keep being told apart from the rank floor.
    """

    def test_fan_floor_and_rank_floor_are_distinct_reasons(self):
        from game.services import DeezerService
        from game.services.catalog import (
            REJECT_ARTIST_FANS, REJECT_RANK, payload_rejection,
        )

        info = DeezerService().extract_track_info(_track(1, rank=900_000))
        small = Artist(deezer_id=901, name='Small Act', nb_fan=12)
        big = Artist(deezer_id=900, name='Famous Act', nb_fan=2_000_000)

        self.assertEqual(payload_rejection(info, small, directed=False), REJECT_ARTIST_FANS)
        self.assertIsNone(payload_rejection(info, big, directed=False))

        low = DeezerService().extract_track_info(_track(2, rank=10))
        self.assertEqual(payload_rejection(low, big, directed=False), REJECT_RANK)

    def test_a_named_artist_bypasses_both_floors(self):
        from game.services import DeezerService
        from game.services.catalog import payload_rejection

        low = DeezerService().extract_track_info(_track(2, rank=10))
        small = Artist(deezer_id=901, name='Small Act', nb_fan=12)
        self.assertIsNone(payload_rejection(low, small, directed=True))
