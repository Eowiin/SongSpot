"""
All-genre play: how the mix weighs the categories, and what it may serve.

Audio resolution is mocked; these assert which track a round picks.
"""

import itertools
from datetime import timedelta
from io import StringIO
from unittest.mock import MagicMock, patch

from django.core.cache import caches
from django.core.management import call_command
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone

from authentication.models import User
from game.consumers import _pick_tracks
from game.management.commands import refresh_catalog
from game.models import (
    CATEGORY_CHOICES, CatalogSetting, GameScore, Playlist, PlaylistTrack, Track,
)
from game.services import pools

PREVIEW_URL = 'https://cdn.test/preview.mp3'

_deezer_ids = itertools.count(9_000_000)


def _stock(category, *titles):
    playlist = Playlist.objects.create(name=category.title(), category=category)
    for order, title in enumerate(titles):
        PlaylistTrack.objects.create(
            playlist=playlist, track=_track(title), order_in_playlist=order,
        )
    return playlist


def _release_of(track, title=None):
    """Another Deezer release of the same song — the best-of next to the album."""
    return Track.objects.create(
        title=title or track.title,
        artist=track.artist,
        has_preview=True,
        deezer_id=next(_deezer_ids),
        rank=400_000,
        is_curated=True,
    )


def _track(title):
    return Track.objects.create(
        title=title,
        artist=f'{title} Artist',
        has_preview=True,
        deezer_id=next(_deezer_ids),
        rank=900_000,
        is_curated=True,
    )


class PoolsTestCase(TestCase):
    def setUp(self):
        self._reset_caches()
        self.pop = _stock('pop', 'Pop One', 'Pop Two', 'Pop Three')
        self.rock = _stock('rock', 'Rock One', 'Rock Two', 'Rock Three')
        self.kpop = _stock('kpop', 'Kpop One')
        self.user = User.objects.create_user(
            username='player', email='player@example.com', password='testpass123',
        )

    def tearDown(self):
        self._reset_caches()

    @staticmethod
    def _reset_caches():
        # The weights live under the `deezer` alias, which `cache.clear()` on
        # `default` does not reach.
        for alias in caches:
            caches[alias].clear()
        CatalogSetting.clear_cache()

    def _sessions(self, genre, count, days_ago=0):
        scores = GameScore.objects.bulk_create(
            GameScore(user=self.user, genre=genre) for _ in range(count)
        )
        if days_ago:
            GameScore.objects.filter(pk__in=[s.pk for s in scores]).update(
                played_at=timezone.now() - timedelta(days=days_ago),
            )

    def _ids(self, playlist):
        return {
            str(track_id) for track_id in
            PlaylistTrack.objects.filter(playlist=playlist).values_list('track_id', flat=True)
        }


class MixWeightsTests(PoolsTestCase):
    def test_weights_follow_what_players_choose(self):
        self._sessions('pop', 30)
        self._sessions('rock', 10)
        weights = pools.mix_weights()
        self.assertAlmostEqual(weights[str(self.pop.id)] / weights[str(self.rock.id)], 3.0)

    def test_a_category_nobody_chose_keeps_a_share(self):
        self._sessions('pop', 30)
        self.assertGreater(pools.mix_weights()[str(self.kpop.id)], 0)

    def test_an_empty_category_is_left_out(self):
        empty = Playlist.objects.create(name='J-pop', category='jpop')
        self._sessions('jpop', 50)
        self.assertNotIn(str(empty.id), pools.mix_weights())

    def test_merged_categories_count_towards_the_one_they_became(self):
        latino = _stock('latino', 'Latino One')
        self._sessions('reggaeton', 6)
        self._sessions('latin', 4)
        self._sessions('pop', 10)
        weights = pools.mix_weights()
        self.assertAlmostEqual(weights[str(latino.id)], weights[str(self.pop.id)])

    def test_old_sessions_no_longer_count(self):
        self._sessions('pop', 10)
        self._sessions('rock', 50, days_ago=60)
        weights = pools.mix_weights()
        self.assertLess(weights[str(self.rock.id)], weights[str(self.pop.id)])

    def test_without_history_it_weighs_by_pool_size(self):
        weights = pools.mix_weights()
        self.assertAlmostEqual(weights[str(self.pop.id)] / weights[str(self.kpop.id)], 3.0)

    def test_all_genre_sessions_are_not_a_choice_of_category(self):
        self._sessions(pools.MIX_GENRE, 40)
        weights = pools.mix_weights()
        self.assertAlmostEqual(weights[str(self.pop.id)] / weights[str(self.kpop.id)], 3.0)

    def test_the_order_covers_every_stocked_category(self):
        self.assertEqual(
            set(pools.mix_order()),
            {str(self.pop.id), str(self.rock.id), str(self.kpop.id)},
        )


@patch('game.services.previews.resolve', return_value=PREVIEW_URL)
class MixedRoundTests(PoolsTestCase):
    def setUp(self):
        super().setUp()
        # Popular, playable, and in no category: the mix must never reach it.
        self.outsider = _track('Outside Every Category')

    def _round(self, **params):
        return self.client.get(reverse('game:next_song'), {'mix': '1', **params})

    def test_a_mixed_round_never_leaves_the_categories(self, _resolve):
        in_categories = self._ids(self.pop) | self._ids(self.rock) | self._ids(self.kpop)
        for _ in range(25):
            response = self._round()
            self.assertEqual(response.status_code, 200)
            self.assertIn(response.data['id'], in_categories)

    def test_a_category_already_heard_hands_over_to_another(self, _resolve):
        heard = self._ids(self.pop) | self._ids(self.kpop)
        for _ in range(10):
            response = self._round(exclude=','.join(heard))
            self.assertEqual(response.status_code, 200)
            self.assertIn(response.data['id'], self._ids(self.rock))

    def test_404_once_every_category_has_been_heard(self, _resolve):
        heard = self._ids(self.pop) | self._ids(self.rock) | self._ids(self.kpop)
        response = self._round(exclude=','.join(heard))
        self.assertEqual(response.status_code, 404)

    def test_a_named_category_wins_over_mix(self, _resolve):
        for _ in range(10):
            response = self._round(playlist=str(self.rock.id))
            self.assertIn(response.data['id'], self._ids(self.rock))

    def test_503_when_the_audio_cannot_be_reached(self, resolve):
        resolve.return_value = None
        self.assertEqual(self._round().status_code, 503)


class MixPopularityTests(PoolsTestCase):
    def _rank(self, playlist, ranks):
        links = list(
            PlaylistTrack.objects.filter(playlist=playlist).order_by('order_in_playlist')
        )
        for link, rank in zip(links, ranks):
            link.song_rank = rank
        PlaylistTrack.objects.bulk_update(links, ['song_rank'])
        return [str(link.track_id) for link in links]

    def _mixed(self, playlist):
        return {str(i) for i in pools.mix_tracks(playlist.id).values_list('id', flat=True)}

    def test_the_least_known_part_of_a_category_is_left_out(self):
        ids = self._rank(self.pop, [900_000, 300_000, 200_000])
        self.assertEqual(self._mixed(self.pop), {ids[0], ids[1]})

    def test_a_well_known_song_is_kept_past_the_top_half(self):
        ids = self._rank(self.pop, [900_000, 800_000, 650_000])
        self.assertEqual(self._mixed(self.pop), set(ids))

    def test_a_category_not_ranked_yet_plays_in_full(self):
        self.assertEqual(self._mixed(self.rock), self._ids(self.rock))

    def test_a_match_skips_the_least_known_songs(self):
        ids = self._rank(self.pop, [900_000, 850_000, 100_000])
        for _ in range(10):
            self.assertNotIn(ids[2], {str(t.id) for t in _pick_tracks(None, 7)})


@patch('game.services.previews.resolve', return_value=PREVIEW_URL)
class SameSongTwiceTests(PoolsTestCase):
    """
    One song, several releases: it may open a run only once.

    Deezer holds a row per release, so the album cut and the best-of cut are
    two tracks with two IDs. Excluding what has been played by ID alone let a
    run serve the same song again under its other release.
    """

    def setUp(self):
        super().setUp()
        self.album = Track.objects.get(title='Kpop One')
        self.best_of = _release_of(self.album)
        PlaylistTrack.objects.create(
            playlist=self.kpop, track=self.best_of, order_in_playlist=1,
        )

    def _round(self, **params):
        return self.client.get(reverse('game:next_song'), {'mix': '1', **params})

    def test_the_other_release_is_not_served_again(self, _resolve):
        heard = self._ids(self.pop) | self._ids(self.rock) | {str(self.album.id)}
        response = self._round(exclude=','.join(heard))
        self.assertEqual(
            response.status_code, 404,
            'the best-of cut of a song already heard is not a new round',
        )

    def test_a_reissued_title_counts_as_the_same_song(self, _resolve):
        # Deezer titles the same song differently per release. Not a variant
        # marker — `(Live)` would already be excluded from picks — but the
        # kind of difference a re-release carries: a credited guest, a
        # language tag, a soundtrack mention.
        self.best_of.title = 'Kpop One (feat. Someone)'
        self.best_of.save()
        heard = self._ids(self.pop) | self._ids(self.rock) | {str(self.album.id)}
        self.assertEqual(self._round(exclude=','.join(heard)).status_code, 404)

    def test_a_different_song_still_plays(self, _resolve):
        heard = self._ids(self.pop) | self._ids(self.rock)
        response = self._round(exclude=','.join(heard))
        self.assertEqual(response.status_code, 200)
        self.assertIn(
            response.data['id'], {str(self.album.id), str(self.best_of.id)},
        )

    def test_a_match_never_draws_one_song_twice(self, _resolve):
        for _ in range(20):
            picks = _pick_tracks(None, 8)
            songs = [(t.norm_title, t.norm_artist) for t in picks]
            self.assertEqual(len(songs), len(set(songs)), songs)


class DuelPickTests(PoolsTestCase):
    def setUp(self):
        super().setUp()
        self.outsider = _track('Outside Every Category')

    def test_a_match_without_a_category_is_drawn_from_the_categories(self):
        picks = _pick_tracks(None, 5)
        self.assertEqual(len(picks), 5)
        self.assertEqual(len({t.id for t in picks}), 5)
        self.assertNotIn(self.outsider.id, {t.id for t in picks})

    def test_a_named_category_stays_in_that_category(self):
        picks = _pick_tracks(str(self.rock.id), 5)
        self.assertEqual({str(t.id) for t in picks}, self._ids(self.rock))

    def test_empty_categories_still_start_a_match(self):
        PlaylistTrack.objects.all().delete()
        self.assertTrue(_pick_tracks(None, 5))


class RefreshCatalogSourcesTests(TestCase):
    def test_every_category_is_sourced_from_editorial_playlists(self):
        self.assertEqual(
            set(refresh_catalog.SOURCES), {key for key, _ in CATEGORY_CHOICES},
        )
        for category, playlist_ids in refresh_catalog.SOURCES.items():
            with self.subTest(category=category):
                self.assertTrue(playlist_ids)
                self.assertTrue(all(isinstance(pid, int) for pid in playlist_ids))

    def test_a_song_is_ranked_by_its_best_known_release(self):
        playlist = Playlist.objects.create(name='Rock', category='rock')
        listed = Track.objects.create(
            title='Song', artist='Band', has_preview=True,
            deezer_id=next(_deezer_ids), rank=120_000,
        )
        Track.objects.create(
            title='Song', artist='Band', has_preview=True,
            deezer_id=next(_deezer_ids), rank=870_000,
        )
        PlaylistTrack.objects.create(playlist=playlist, track=listed, order_in_playlist=0)
        refresh_catalog.Command._rank_songs(playlist)
        self.assertEqual(PlaylistTrack.objects.get(playlist=playlist).song_rank, 870_000)

    def test_a_long_playlist_is_read_to_the_end(self):
        deezer = MagicMock()
        deezer.get_playlist_tracks.side_effect = [
            [{'id': i} for i in range(100)],
            [{'id': i} for i in range(100, 105)],
        ]
        payloads = refresh_catalog.Command._playlist_payloads(deezer, 42)
        self.assertEqual(len(payloads), 105)
        deezer.get_playlist_tracks.assert_called_with(42, limit=100, index=100)

    @patch('game.management.commands.refresh_catalog.DeezerService')
    def test_a_fresh_database_gets_every_category(self, deezer_cls):
        # Migrations create Latino and Disco; the command adds the rest, once.
        deezer_cls.return_value.get_playlist_tracks.return_value = []
        call_command('refresh_catalog', stdout=StringIO())
        call_command('refresh_catalog', stdout=StringIO())
        self.assertEqual(
            sorted(Playlist.objects.values_list('category', flat=True)),
            sorted(refresh_catalog.SOURCES),
        )

    @patch('game.management.commands.refresh_catalog.DeezerService')
    def test_a_refresh_never_reads_a_chart(self, deezer_cls):
        deezer = deezer_cls.return_value
        deezer.get_playlist_tracks.return_value = []
        Playlist.objects.create(name='Pop', category='pop', deezer_genre_id=132)
        call_command(
            'refresh_catalog', '--category', 'pop', '--dry-run', stdout=StringIO(),
        )
        deezer.get_genre_chart_tracks.assert_not_called()
        self.assertEqual(
            deezer.get_playlist_tracks.call_count, len(refresh_catalog.SOURCES['pop']),
        )
