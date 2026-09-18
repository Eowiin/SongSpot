from datetime import timedelta
import itertools
from unittest import mock

from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APITestCase
from rest_framework import status
from rest_framework_simplejwt.tokens import RefreshToken
from authentication.models import User
from .models import (
    Artist, Track, FavouriteArtist, GameScore, UserBest, Playlist, PlaylistTrack,
    SearchEnrichment,
)
from .services import catalog
from .services.matching import normalize_artist, normalize_title

from django.core.cache import cache


def _make_user(username, email=None, password='testpass123'):
    return User.objects.create_user(
        username=username,
        email=email or f'{username}@example.com',
        password=password,
    )


_next_deezer_id = itertools.count(1)


def _make_track(title='Test Song', artist='Test Artist', genre='pop'):
    return Track.objects.create(
        title=title,
        artist=artist,
        genre=genre,
        has_preview=True,
        deezer_id=next(_next_deezer_id),
    )


def _bearer(user):
    return f'Bearer {str(RefreshToken.for_user(user).access_token)}'


class TrackModelTests(TestCase):
    def test_create_track(self):
        track = _make_track()
        self.assertEqual(track.title, 'Test Song')
        self.assertEqual(track.artist, 'Test Artist')
        self.assertIsNotNone(track.id)

    def test_track_string_representation(self):
        track = _make_track()
        self.assertEqual(str(track), 'Test Song - Test Artist')

    def test_optional_fields_nullable(self):
        track = Track.objects.create(
            title='Bare Track',
            artist='Bare Artist',
            has_preview=True,
        deezer_id=next(_next_deezer_id),
        )
        self.assertIsNone(track.genre)
        self.assertIsNone(track.release_year)
        self.assertIsNone(track.cover_url)


class GameScoreModelTests(TestCase):
    def setUp(self):
        self.user = _make_user('scorer')

    def test_create_game_score(self):
        score = GameScore.objects.create(
            user=self.user,
            songs_played=10,
            songs_correct=7,
            best_streak=5,
            total_score=120,
            difficulty='medium',
        )
        self.assertEqual(score.songs_played, 10)
        self.assertEqual(score.total_score, 120)

    def test_genre_and_artist_filter_default_blank(self):
        score = GameScore.objects.create(
            user=self.user,
            songs_played=5,
            songs_correct=3,
            best_streak=2,
            total_score=40,
        )
        self.assertIsNone(score.genre)
        self.assertEqual(score.artist_filter, '')

    def test_string_representation(self):
        score = GameScore.objects.create(
            user=self.user,
            genre='pop',
            songs_played=5,
            songs_correct=5,
            best_streak=5,
            total_score=80,
        )
        self.assertIn('scorer', str(score))
        self.assertIn('pop', str(score))


class UserBestModelTests(TestCase):
    def setUp(self):
        self.user = _make_user('best_player')

    def test_created_with_defaults(self):
        best = UserBest.objects.create(user=self.user)
        self.assertEqual(best.best_score_overall, 0)
        self.assertEqual(best.best_streak_overall, 0)
        self.assertEqual(best.total_songs_played, 0)
        self.assertEqual(best.per_genre, {})

    def test_update_from_score_improves_bests(self):
        best = UserBest.objects.create(user=self.user)
        score = GameScore.objects.create(
            user=self.user,
            genre='hiphop',
            songs_played=8,
            songs_correct=6,
            best_streak=4,
            total_score=200,
        )
        changed = best.update_from_score(score)
        best.refresh_from_db()
        self.assertTrue(changed)
        self.assertEqual(best.best_score_overall, 200)
        self.assertEqual(best.best_streak_overall, 4)
        self.assertEqual(best.total_songs_played, 8)
        self.assertEqual(best.per_genre['hiphop']['best_score'], 200)

    def test_update_from_score_no_change_when_lower(self):
        best = UserBest.objects.create(
            user=self.user,
            best_score_overall=500,
            best_streak_overall=10,
        )
        score = GameScore.objects.create(
            user=self.user,
            songs_played=3,
            songs_correct=1,
            best_streak=2,
            total_score=20,
        )
        changed = best.update_from_score(score)
        best.refresh_from_db()
        self.assertFalse(changed)
        self.assertEqual(best.best_score_overall, 500)

    def test_total_songs_always_accumulates(self):
        best = UserBest.objects.create(user=self.user, total_songs_played=5)
        score = GameScore.objects.create(
            user=self.user,
            songs_played=3,
            songs_correct=2,
            best_streak=1,
            total_score=30,
        )
        best.update_from_score(score)
        best.refresh_from_db()
        self.assertEqual(best.total_songs_played, 8)


class PlaylistListViewTests(APITestCase):
    url = '/api/game/categories/'

    def setUp(self):
        cache.clear()
        self.pop_playlist = Playlist.objects.create(name='Pop', category='pop')
        self.hiphop_playlist = Playlist.objects.create(name='Hip-Hop / Rap', category='hiphop')
        self.empty_playlist = Playlist.objects.create(name='Rock', category='rock')
        t1 = _make_track(genre='pop')
        t2 = _make_track(title='Pop Song 2', genre='pop')
        t3 = _make_track(title='Hip Hop Song', artist='Rapper', genre='hiphop')
        PlaylistTrack.objects.create(playlist=self.pop_playlist, track=t1, order_in_playlist=1)
        PlaylistTrack.objects.create(playlist=self.pop_playlist, track=t2, order_in_playlist=2)
        PlaylistTrack.objects.create(playlist=self.hiphop_playlist, track=t3, order_in_playlist=1)

    def test_returns_playlists_with_track_count(self):
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        by_category = {r['category']: r['track_count'] for r in response.data}
        self.assertEqual(by_category.get('pop'), 2)
        self.assertEqual(by_category.get('hiphop'), 1)

    def test_excludes_empty_playlists(self):
        response = self.client.get(self.url)
        categories = [r['category'] for r in response.data]
        self.assertNotIn('rock', categories)

    def test_accessible_without_auth(self):
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_each_entry_has_required_fields(self):
        response = self.client.get(self.url)
        for entry in response.data:
            self.assertIn('id', entry)
            self.assertIn('name', entry)
            self.assertIn('category', entry)
            self.assertIn('track_count', entry)


class NextSongViewTests(APITestCase):
    url = '/api/game/next-song/'

    def setUp(self):
        cache.clear()
        self.pop_playlist = Playlist.objects.create(name='Pop', category='pop')
        self.rock_playlist = Playlist.objects.create(name='Rock', category='rock')
        self.pop1 = _make_track(title='Pop Song 1', artist='Pop Artist', genre='pop')
        self.pop2 = _make_track(title='Pop Song 2', artist='Pop Artist', genre='pop')
        self.rock = _make_track(title='Rock Song', artist='Rock Artist', genre='rock')
        PlaylistTrack.objects.create(playlist=self.pop_playlist, track=self.pop1, order_in_playlist=1)
        PlaylistTrack.objects.create(playlist=self.pop_playlist, track=self.pop2, order_in_playlist=2)
        PlaylistTrack.objects.create(playlist=self.rock_playlist, track=self.rock, order_in_playlist=1)

    def test_returns_a_track(self):
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('id', response.data)
        self.assertIn('title', response.data)
        self.assertIn('preview_url', response.data)

    def test_playlist_filter_returns_matching_tracks(self):
        response = self.client.get(self.url, {'playlist': str(self.rock_playlist.id)})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['title'], 'Rock Song')

    def test_artist_filter(self):
        _make_track(title='Artist Song', artist='Unique Solo Artist', genre='pop')
        response = self.client.get(self.url, {'artist': 'Unique Solo'})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('Unique Solo Artist', response.data['artist'])

    def test_exclude_ids_filters_out_seen_tracks(self):
        exclude = str(self.pop1.id)
        for _ in range(5):
            response = self.client.get(self.url, {'playlist': str(self.pop_playlist.id), 'exclude': exclude})
            self.assertEqual(response.status_code, status.HTTP_200_OK)
            self.assertNotEqual(response.data['id'], exclude)

    def test_404_when_playlist_is_empty(self):
        empty = Playlist.objects.create(name='Empty', category='kpop')
        response = self.client.get(self.url, {'playlist': str(empty.id)})
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_accessible_without_auth(self):
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)


class ArtistListViewTests(APITestCase):
    url = '/api/game/artists/'

    def setUp(self):
        cache.clear()
        _make_track(title='Song A', artist='Beyoncé')
        _make_track(title='Song B', artist='The Beatles')
        _make_track(title='Song C', artist='Beatles Revival Band')

    def test_returns_matching_artists(self):
        response = self.client.get(self.url, {'q': 'Beat'})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        names = [a['name'] for a in response.data]
        self.assertIn('The Beatles', names)
        self.assertIn('Beatles Revival Band', names)

    def test_empty_for_short_query(self):
        response = self.client.get(self.url, {'q': 'B'})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data, [])

    def test_each_entry_has_name_and_picture_url(self):
        response = self.client.get(self.url, {'q': 'Bey'})
        for entry in response.data:
            self.assertIn('name', entry)
            self.assertIn('picture_url', entry)

    def test_accessible_without_auth(self):
        response = self.client.get(self.url, {'q': 'Beat'})
        self.assertEqual(response.status_code, status.HTTP_200_OK)


class ArtistTrendingViewTests(APITestCase):
    url = '/api/game/artists/trending/'

    def setUp(self):
        cache.clear()
        self.user = _make_user('trend_user')
        GameScore.objects.create(
            user=self.user, artist_filter='Drake',
            songs_played=5, songs_correct=4, best_streak=3, total_score=80,
        )
        GameScore.objects.create(
            user=self.user, artist_filter='Drake',
            songs_played=3, songs_correct=2, best_streak=2, total_score=40,
        )
        GameScore.objects.create(
            user=self.user, artist_filter='Adele',
            songs_played=2, songs_correct=1, best_streak=1, total_score=20,
        )

    def test_returns_trending_artists(self):
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        names = [a['name'] for a in response.data]
        self.assertIn('Drake', names)
        self.assertIn('Adele', names)

    def test_most_played_artist_appears_first(self):
        response = self.client.get(self.url)
        self.assertEqual(response.data[0]['name'], 'Drake')

    def test_old_scores_excluded(self):
        old_score = GameScore.objects.create(
            user=self.user, artist_filter='Old Artist',
            songs_played=100, songs_correct=100, best_streak=100, total_score=9999,
        )
        old_score.played_at = timezone.now() - timedelta(days=60)
        old_score.save(update_fields=['played_at'])
        response = self.client.get(self.url)
        names = [a['name'] for a in response.data]
        self.assertNotIn('Old Artist', names)

    def test_accessible_without_auth(self):
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)


class FavouriteArtistViewTests(APITestCase):
    url = '/api/game/artists/favourites/'

    def setUp(self):
        self.user = _make_user('fav_user')
        self.client.credentials(HTTP_AUTHORIZATION=_bearer(self.user))

    def test_list_empty_by_default(self):
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data, [])

    def test_add_favourite_artist(self):
        response = self.client.post(self.url, {'artist_name': 'Kendrick Lamar'}, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(FavouriteArtist.objects.filter(user=self.user, artist_name='Kendrick Lamar').exists())

    def test_add_favourite_idempotent(self):
        self.client.post(self.url, {'artist_name': 'Kendrick Lamar'}, format='json')
        self.client.post(self.url, {'artist_name': 'Kendrick Lamar'}, format='json')
        self.assertEqual(
            FavouriteArtist.objects.filter(user=self.user, artist_name='Kendrick Lamar').count(), 1
        )

    def test_list_shows_added_artists(self):
        FavouriteArtist.objects.create(user=self.user, artist_name='Jay-Z')
        response = self.client.get(self.url)
        names = [a['name'] for a in response.data]
        self.assertIn('Jay-Z', names)

    def test_add_requires_artist_name(self):
        response = self.client.post(self.url, {}, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_requires_authentication(self):
        self.client.credentials()
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)


class FavouriteArtistDetailViewTests(APITestCase):
    def setUp(self):
        self.user = _make_user('fav_detail_user')
        self.client.credentials(HTTP_AUTHORIZATION=_bearer(self.user))
        FavouriteArtist.objects.create(user=self.user, artist_name='Rihanna')

    def test_delete_favourite_artist(self):
        response = self.client.delete('/api/game/artists/favourites/Rihanna/')
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(FavouriteArtist.objects.filter(user=self.user, artist_name='Rihanna').exists())

    def test_delete_nonexistent_is_idempotent(self):
        response = self.client.delete('/api/game/artists/favourites/Unknown/')
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)

    def test_delete_requires_authentication(self):
        self.client.credentials()
        response = self.client.delete('/api/game/artists/favourites/Rihanna/')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)


class SearchTracksViewTests(APITestCase):
    url = '/api/game/tracks/search/'

    def setUp(self):
        cache.clear()
        _make_track(title='Bohemian Rhapsody', artist='Queen', genre='rock')
        _make_track(title='Somebody That I Used to Know', artist='Gotye', genre='pop')
        _make_track(title='Another Brick', artist='Pink Floyd', genre='rock')

    def test_search_by_title(self):
        response = self.client.get(self.url, {'q': 'Bohemian'})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        titles = [t['title'] for t in response.data]
        self.assertIn('Bohemian Rhapsody', titles)

    def test_search_by_artist(self):
        response = self.client.get(self.url, {'q': 'Gotye'})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)

    def test_short_query_returns_empty(self):
        response = self.client.get(self.url, {'q': 'B'})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data, [])

    def test_no_preview_url_in_search_results(self):
        response = self.client.get(self.url, {'q': 'Brick'})
        for entry in response.data:
            self.assertNotIn('preview_url', entry)

    def test_accessible_without_auth(self):
        response = self.client.get(self.url, {'q': 'Queen'})
        self.assertEqual(response.status_code, status.HTTP_200_OK)


class SubmitScoreViewTests(APITestCase):
    url = '/api/game/score/'

    def setUp(self):
        self.user = _make_user('scorer')
        self.client.credentials(HTTP_AUTHORIZATION=_bearer(self.user))

    def _payload(self, **overrides):
        base = {
            'genre': 'pop',
            'artist_filter': '',
            'difficulty': 'medium',
            'songs_played': 10,
            'songs_correct': 7,
            'best_streak': 5,
            'total_score': 120,
        }
        base.update(overrides)
        return base

    def test_submit_score_creates_game_score(self):
        response = self.client.post(self.url, self._payload(), format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(GameScore.objects.filter(user=self.user).exists())

    def test_submit_score_creates_user_best(self):
        self.client.post(self.url, self._payload(), format='json')
        self.assertTrue(UserBest.objects.filter(user=self.user).exists())
        best = UserBest.objects.get(user=self.user)
        self.assertEqual(best.best_score_overall, 120)

    def test_submit_score_response_has_required_fields(self):
        response = self.client.post(self.url, self._payload(), format='json')
        for field in ('id', 'genre', 'songs_played', 'songs_correct', 'best_streak', 'total_score'):
            self.assertIn(field, response.data)

    def test_second_better_score_updates_user_best(self):
        self.client.post(self.url, self._payload(total_score=100), format='json')
        self.client.post(self.url, self._payload(total_score=300, best_streak=10), format='json')
        best = UserBest.objects.get(user=self.user)
        self.assertEqual(best.best_score_overall, 300)
        self.assertEqual(best.best_streak_overall, 10)

    def test_artist_filter_score_stored(self):
        response = self.client.post(
            self.url,
            self._payload(genre='', artist_filter='Daft Punk'),
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        score = GameScore.objects.get(id=response.data['id'])
        self.assertEqual(score.artist_filter, 'Daft Punk')
        self.assertIsNone(score.genre)

    def test_requires_authentication(self):
        self.client.credentials()
        response = self.client.post(self.url, self._payload(), format='json')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_missing_required_fields_returns_400(self):
        response = self.client.post(self.url, {}, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_difficulty_choices_accepted(self):
        for diff in ('easy', 'medium', 'hard'):
            response = self.client.post(self.url, self._payload(difficulty=diff), format='json')
            self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_invalid_difficulty_rejected(self):
        response = self.client.post(self.url, self._payload(difficulty='expert'), format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class UserStatsViewTests(APITestCase):
    url = '/api/game/stats/'

    def setUp(self):
        self.user = _make_user('stats_user')
        self.client.credentials(HTTP_AUTHORIZATION=_bearer(self.user))

    def test_returns_default_stats_for_new_user(self):
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['best_score_overall'], 0)
        self.assertEqual(response.data['total_songs_played'], 0)

    def test_returns_existing_user_best(self):
        UserBest.objects.create(
            user=self.user,
            best_score_overall=500,
            best_streak_overall=8,
            total_songs_played=40,
        )
        response = self.client.get(self.url)
        self.assertEqual(response.data['best_score_overall'], 500)
        self.assertEqual(response.data['best_streak_overall'], 8)

    def test_requires_authentication(self):
        self.client.credentials()
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_response_has_required_fields(self):
        response = self.client.get(self.url)
        for field in ('best_score_overall', 'best_streak_overall',
                      'total_songs_played', 'total_songs_correct', 'per_genre'):
            self.assertIn(field, response.data)


class LeaderboardViewTests(APITestCase):
    url = '/api/game/leaderboard/'

    def setUp(self):
        self.user = _make_user('leaderboard_user')
        self.client.credentials(HTTP_AUTHORIZATION=_bearer(self.user))
        self.other = _make_user('other_user')

        GameScore.objects.create(
            user=self.user, genre='pop',
            songs_played=10, songs_correct=8, best_streak=5, total_score=200,
        )
        GameScore.objects.create(
            user=self.other, genre='pop',
            songs_played=10, songs_correct=10, best_streak=10, total_score=400,
        )
        GameScore.objects.create(
            user=self.user, genre='rock',
            songs_played=5, songs_correct=3, best_streak=2, total_score=50,
        )

    def test_returns_scores_ordered_by_total_score_desc(self):
        response = self.client.get(self.url, {'timeframe': 'alltime'})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        scores = [entry['total_score'] for entry in response.data]
        self.assertEqual(scores, sorted(scores, reverse=True))

    def test_genre_filter(self):
        response = self.client.get(self.url, {'timeframe': 'alltime', 'genre': 'rock'})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        for entry in response.data:
            self.assertEqual(entry['genre'], 'rock')

    def test_daily_timeframe_excludes_old_scores(self):
        old_score = GameScore.objects.create(
            user=self.user, genre='pop',
            songs_played=5, songs_correct=5, best_streak=5, total_score=9999,
        )
        old_score.played_at = timezone.now() - timedelta(days=3)
        old_score.save(update_fields=['played_at'])
        response = self.client.get(self.url, {'timeframe': 'daily'})
        score_ids = [e['id'] for e in response.data]
        self.assertNotIn(str(old_score.id), score_ids)

    def test_alltime_includes_all_scores(self):
        response = self.client.get(self.url, {'timeframe': 'alltime'})
        self.assertEqual(len(response.data), 3)

    def test_limit_param_respected(self):
        response = self.client.get(self.url, {'timeframe': 'alltime', 'limit': 2})
        self.assertEqual(response.status_code, status.HTTP_200_OK, response.data)
        self.assertLessEqual(len(response.data), 2)

    def test_response_entries_have_user_field(self):
        response = self.client.get(self.url, {'timeframe': 'alltime'})
        for entry in response.data:
            self.assertIn('user', entry)
            self.assertIn('username', entry['user'])

    def test_requires_authentication(self):
        self.client.credentials()
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)


class MigrateGuestStatsViewTests(APITestCase):
    url = '/api/game/migrate-guest-stats/'

    def setUp(self):
        self.user = _make_user('migrator')
        self.client.credentials(HTTP_AUTHORIZATION=_bearer(self.user))

    def _payload(self, **overrides):
        base = {
            'best_score': 150,
            'best_streak': 6,
            'songs_played': 20,
            'songs_correct': 14,
        }
        base.update(overrides)
        return base

    def test_migrate_creates_user_best(self):
        response = self.client.post(self.url, self._payload(), format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['status'], 'migrated')
        best = UserBest.objects.get(user=self.user)
        self.assertEqual(best.best_score_overall, 150)
        self.assertEqual(best.total_songs_played, 20)

    def test_migrate_merges_keeps_higher_existing_best(self):
        UserBest.objects.create(
            user=self.user,
            best_score_overall=200,
            best_streak_overall=3,
            total_songs_played=10,
            total_songs_correct=7,
        )
        response = self.client.post(self.url, self._payload(best_score=100), format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        best = UserBest.objects.get(user=self.user)
        self.assertEqual(best.best_score_overall, 200)
        self.assertEqual(best.total_songs_played, 30)

    def test_migrate_applies_higher_guest_score(self):
        UserBest.objects.create(user=self.user, best_score_overall=50)
        self.client.post(self.url, self._payload(best_score=300), format='json')
        best = UserBest.objects.get(user=self.user)
        self.assertEqual(best.best_score_overall, 300)

    def test_nothing_migrated_when_songs_played_zero(self):
        response = self.client.post(self.url, self._payload(songs_played=0), format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['status'], 'nothing_to_migrate')

    def test_requires_authentication(self):
        self.client.credentials()
        response = self.client.post(self.url, self._payload(), format='json')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_missing_fields_returns_400(self):
        response = self.client.post(self.url, {}, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class WebSocketOriginValidatorTests(TestCase):
    """
    The web build connects over WebSockets from a browser, which always sends
    an Origin header. Native clients send none and must never be blocked.
    """

    def setUp(self):
        from .middleware import OriginValidatorMiddleware

        self.sent = []

        async def inner(scope, receive, send):
            self.sent.append({'type': 'reached_inner'})

        self.middleware = OriginValidatorMiddleware(inner)

    def _scope(self, origin=None):
        headers = [(b'host', b'api.example.com')]
        if origin is not None:
            headers.append((b'origin', origin.encode()))
        return {'type': 'websocket', 'path': '/ws/duel/queue/', 'headers': headers}

    def _run(self, scope):
        import asyncio

        async def send(message):
            self.sent.append(message)

        async def receive():
            return {'type': 'websocket.connect'}

        asyncio.run(self.middleware(scope, receive, send))
        return self.sent

    @override_settings(WEBSOCKET_ALLOWED_ORIGINS=['https://play.example.com'])
    def test_allowed_origin_reaches_inner_app(self):
        sent = self._run(self._scope('https://play.example.com'))
        self.assertEqual(sent, [{'type': 'reached_inner'}])

    @override_settings(WEBSOCKET_ALLOWED_ORIGINS=['https://play.example.com'])
    def test_trailing_slash_on_origin_is_tolerated(self):
        sent = self._run(self._scope('https://play.example.com/'))
        self.assertEqual(sent, [{'type': 'reached_inner'}])

    @override_settings(WEBSOCKET_ALLOWED_ORIGINS=['https://play.example.com'])
    def test_disallowed_origin_is_closed(self):
        sent = self._run(self._scope('https://evil.example.com'))
        self.assertEqual(sent, [{'type': 'websocket.close', 'code': 4003}])

    @override_settings(WEBSOCKET_ALLOWED_ORIGINS=['https://play.example.com'])
    def test_missing_origin_is_allowed_for_native_clients(self):
        sent = self._run(self._scope(None))
        self.assertEqual(sent, [{'type': 'reached_inner'}])

    @override_settings(WEBSOCKET_ALLOWED_ORIGINS=[])
    def test_empty_allowlist_disables_the_check(self):
        sent = self._run(self._scope('https://anything.example.com'))
        self.assertEqual(sent, [{'type': 'reached_inner'}])


class CorsHeaderTests(APITestCase):
    """The web build calls the API cross-origin; mobile clients never do."""

    @override_settings(CORS_ALLOWED_ORIGINS=['https://play.example.com'],
                       CORS_ALLOWED_ORIGIN_REGEXES=[])
    def test_allowed_origin_gets_cors_header(self):
        response = self.client.get(
            '/api/game/categories/', HTTP_ORIGIN='https://play.example.com'
        )
        self.assertEqual(
            response.headers.get('Access-Control-Allow-Origin'),
            'https://play.example.com',
        )

    @override_settings(CORS_ALLOWED_ORIGINS=['https://play.example.com'],
                       CORS_ALLOWED_ORIGIN_REGEXES=[])
    def test_unknown_origin_gets_no_cors_header(self):
        response = self.client.get(
            '/api/game/categories/', HTTP_ORIGIN='https://evil.example.com'
        )
        self.assertIsNone(response.headers.get('Access-Control-Allow-Origin'))

    @override_settings(CORS_ALLOWED_ORIGINS=['https://play.example.com'],
                       CORS_ALLOWED_ORIGIN_REGEXES=[])
    def test_preflight_is_answered_without_auth(self):
        response = self.client.options(
            '/api/game/categories/',
            HTTP_ORIGIN='https://play.example.com',
            HTTP_ACCESS_CONTROL_REQUEST_METHOD='GET',
            HTTP_ACCESS_CONTROL_REQUEST_HEADERS='authorization',
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn(
            'authorization',
            response.headers.get('Access-Control-Allow-Headers', ''),
        )


class PlayableQueryShapeTests(TestCase):
    """
    The junk-artist exclusion must reach the database as values, not a query.

    Left lazy it went in as a subquery, and Postgres re-derived it on every
    round: a sequential scan of all 428k artists to recover the ~700 flagged
    ones, on the hot path of the busiest endpoint in the game. Nothing about
    the results changes when it regresses, so only the query shape catches it.
    """

    def setUp(self):
        cache.clear()
        catalog.clear_junk_artist_cache()

    def tearDown(self):
        catalog.clear_junk_artist_cache()

    def _track_by(self, artist, deezer_artist_id):
        track = _make_track(artist=artist)
        Track.objects.filter(pk=track.pk).update(deezer_artist_id=deezer_artist_id)
        return track

    def test_only_indexed_hard_blocks_use_an_artist_subquery(self):
        Artist.objects.create(deezer_id=9001, name='Tribute Band', is_junk=True)
        sql = str(catalog.playable(Track.objects.all()).query)
        self.assertIn('"is_blocked"', sql)
        self.assertNotIn('"is_junk"', sql)

    def test_junk_artist_tracks_stay_out_of_undirected_picks(self):
        Artist.objects.create(deezer_id=9002, name='Tribute Band', is_junk=True)
        junk = self._track_by('Tribute Band', 9002)
        keeper = self._track_by('Real Artist', 9003)

        playable = catalog.playable(Track.objects.all())
        self.assertIn(keeper.pk, {t.pk for t in playable})
        self.assertNotIn(junk.pk, {t.pk for t in playable})

    def test_blocking_an_artist_takes_effect_without_waiting_for_the_ttl(self):
        artist = Artist.objects.create(deezer_id=9004, name='Ordinary Act')
        track = self._track_by('Ordinary Act', 9004)
        # Warm both cache tiers before the block, which is the case that would
        # otherwise serve a blocked artist for up to the local TTL.
        self.assertIn(track.pk, {t.pk for t in catalog.playable(Track.objects.all())})

        artist.is_blocked = True
        artist.save()

        self.assertNotIn(track.pk, {t.pk for t in catalog.playable(Track.objects.all())})

    def test_directed_picks_respect_hard_blocks(self):
        Artist.objects.create(deezer_id=9005, name='Ordinary Act', is_blocked=True)
        track = self._track_by('Ordinary Act', 9005)
        directed = catalog.playable(Track.objects.all(), directed=True)
        self.assertNotIn(track.pk, {t.pk for t in directed})


class ShortTokenSearchTests(TestCase):
    """
    A token too short for a trigram index must not reach the table unanchored,
    and must not make a song unfindable either.

    `%xx%` cannot use a trigram index — they store three-character sequences —
    so a two-letter word made Postgres read all 1.6M rows across three parallel
    workers, 1282ms a go, on the endpoint players hit per keystroke. The first
    fix anchored every short word to the start of the field, which lost any
    song once the player typed past its first word: `feu de bois` found
    nothing, because `de` does not begin *Feu de bois*. It was reported from
    the Play Store.
    """

    def setUp(self):
        cache.clear()

    def test_short_token_matches_at_the_start(self):
        _make_track(title='Beautiful Day', artist='U2')
        results = catalog.search_tracks('u2')
        self.assertEqual([t.artist for t in results], ['U2'])

    def test_short_token_matches_a_later_word(self):
        # Word indexing avoids the old field-start-only compromise.
        _make_track(title='Do It', artist='Chase Atlantic')
        self.assertEqual([t.title for t in catalog.search_tracks('it')], ['Do It'])

    def test_short_token_query_carries_no_leading_wildcard(self):
        sql = str(Track.objects.filter(catalog._query_filter('u2')).query)
        self.assertNotIn('%u2%', sql)
        self.assertIn('LIKE u2%', sql)

    def test_long_token_still_matches_mid_field(self):
        _make_track(title='Blinding Lights', artist='The Weeknd')
        results = catalog.search_tracks('lights')
        self.assertEqual([t.title for t in results], ['Blinding Lights'])

    def test_mixed_lengths_apply_their_own_rule(self):
        _make_track(title='Do It', artist='Chase Atlantic')
        _make_track(title='Doing Fine', artist='Chase Atlantic')
        # `do` has to begin a word, `chase` can sit anywhere — both titles
        # start with "do", so the long token is what separates them.
        results = catalog.search_tracks('do chase')
        self.assertEqual(
            sorted(t.title for t in results), ['Do It', 'Doing Fine'],
        )

    def test_a_title_stays_found_while_it_is_typed(self):
        _make_track(title='Feu de bois', artist='Damso')
        for query in ('feu', 'feu de', 'feu de b', 'feu de bois', 'damso feu de'):
            with self.subTest(query=query):
                results = catalog.search_tracks(query)
                self.assertIn('Feu de bois', [t.title for t in results])

    def test_a_short_word_has_to_begin_a_word(self):
        # `eu` sits inside `feu` but begins no word of the title or artist.
        _make_track(title='Feu de bois', artist='Damso')
        self.assertEqual(catalog.search_tracks('bois eu'), [])

    def test_short_words_alone_match_as_a_phrase(self):
        _make_track(title='Do It', artist='Stray Kids')
        self.assertEqual([t.title for t in catalog.search_tracks('do it')], ['Do It'])

    def test_short_words_alone_match_across_title_and_artist(self):
        _make_track(title='Esquina', artist='UANA')
        self.assertEqual([t.title for t in catalog.search_tracks('es ua')], ['Esquina'])

    def test_a_short_word_next_to_a_long_one_is_anchored_to_a_word(self):
        sql = str(Track.objects.filter(catalog._query_filter('feu de')).query)
        self.assertNotIn('%de%', sql)
        self.assertIn('% de%', sql)

    def test_short_words_alone_carry_no_leading_wildcard(self):
        sql = str(Track.objects.filter(catalog._query_filter('do it')).query)
        self.assertNotIn('LIKE %', sql)

    def test_a_one_letter_word_only_counts_as_part_of_the_phrase(self):
        # `a%` on its own matches hundreds of thousands of rows per field.
        _make_track(title='Take on Me', artist='a-ha')
        self.assertEqual([t.title for t in catalog.search_tracks('a ha')], ['Take on Me'])
        sql = str(Track.objects.filter(catalog._query_filter('a ha')).query)
        self.assertNotIn('LIKE a%', sql)


@mock.patch.object(catalog, '_enrich_later')
@mock.patch.object(catalog, '_enrich_now', return_value=[])
class ExactTitleSearchTests(TestCase):
    """
    A title typed in full must survive more popular rows that merely contain it.

    Once the catalogue held millions of rows, the 150 most popular matches for
    `the motion` were soundtracks "From The Motion Picture", and for `q&a`
    anything containing `and`. Drake's *The Motion* and *Q&A* were in the
    table but in neither list. Reported by a player by email.
    """

    def setUp(self):
        cache.clear()

    def _crowd(self, title, artist, count=160):
        Track.objects.bulk_create(
            Track(
                title=f'{title} {i}', artist=artist, rank=900_000 - i,
                has_preview=True, deezer_id=next(_next_deezer_id),
                norm_title=normalize_title(f'{title} {i}'),
                norm_artist=normalize_artist(artist),
            )
            for i in range(count)
        )

    def _track(self, title, artist, rank):
        track = _make_track(title=title, artist=artist)
        track.rank = rank
        track.save(update_fields=['rank'])
        return track

    def test_an_exact_title_outranks_popular_rows_containing_its_words(self, *_):
        self._crowd('Venom (From The Motion Picture)', 'Eminem')
        self._track('The Motion', 'Drake', 473_341)
        results = catalog.search_tracks('the motion', limit=20)
        self.assertEqual(results[0].title, 'The Motion')

    def test_an_exact_title_outside_the_popular_matches_is_still_found(self, *_):
        self._crowd('Quiet and Alone', 'Henrique & Juliano')
        self._track('Q&A', 'Drake', 461_205)
        results = catalog.search_tracks('Q&A', limit=20)
        self.assertIn('Q&A', [t.title for t in results])

    def test_a_title_named_like_an_artist_does_not_bury_the_artist(self, *_):
        # On prod the boost alone put "Rihanna" by SDM above every Rihanna song.
        self._track("Don't Stop The Music", 'Rihanna', 700_000)
        self._track('We Found Love', 'Rihanna', 690_000)
        self._track('Rihanna', 'SDM', 400_000)
        for query in ('rihanna', 'rihan'):
            with self.subTest(query=query):
                results = catalog.search_tracks(query, limit=20)
                self.assertEqual(
                    [t.artist for t in results[:2]], ['Rihanna', 'Rihanna'],
                )


class EnrichmentClaimTests(TestCase):
    """
    A claim has to outlive the cache, because in the cache it did not.

    Redis sits at its 2GB cap under `allkeys-lru` and a claim is never read
    once written, so it was evicted within hours of a week-long TTL. Each loss
    reopened its query and re-imported the same fifty tracks, which is what
    held ingestion at a floor that never decayed.
    """

    def setUp(self):
        cache.clear()

    def test_first_caller_claims_and_second_does_not(self):
        self.assertTrue(catalog._claim('tracks', 'despacito'))
        self.assertFalse(catalog._claim('tracks', 'despacito'))

    def test_claim_survives_the_cache_being_wiped(self):
        self.assertTrue(catalog._claim('tracks', 'despacito'))
        cache.clear()
        self.assertFalse(catalog._claim('tracks', 'despacito'))

    def test_claim_is_keyed_on_the_normalised_query(self):
        self.assertTrue(catalog._claim('tracks', 'Rosalía'))
        self.assertFalse(catalog._claim('tracks', 'rosalia'))

    def test_kinds_claim_independently(self):
        self.assertTrue(catalog._claim('tracks', 'rosalia'))
        self.assertTrue(catalog._claim('artists', 'rosalia'))

    def test_expired_claim_is_reusable(self):
        self.assertTrue(catalog._claim('tracks', 'despacito'))
        SearchEnrichment.objects.update(
            enriched_at=timezone.now() - timedelta(seconds=catalog.ENRICH_DEDUP_TTL + 60)
        )
        self.assertTrue(catalog._claim('tracks', 'despacito'))

    def test_expired_claim_goes_to_one_caller_only(self):
        self.assertTrue(catalog._claim('tracks', 'despacito'))
        SearchEnrichment.objects.update(
            enriched_at=timezone.now() - timedelta(seconds=catalog.ENRICH_DEDUP_TTL + 60)
        )
        # Two workers racing on the same expired claim: the compare-and-swap
        # inside the UPDATE has to let exactly one of them through.
        self.assertTrue(catalog._claim('tracks', 'despacito'))
        self.assertFalse(catalog._claim('tracks', 'despacito'))

    def test_release_reopens_the_query(self):
        self.assertTrue(catalog._claim('tracks', 'despacito'))
        catalog._release('tracks', 'despacito')
        self.assertTrue(catalog._claim('tracks', 'despacito'))

    def test_blank_query_never_claims(self):
        self.assertFalse(catalog._claim('tracks', '   '))
        self.assertEqual(SearchEnrichment.objects.count(), 0)


class PurgeExpiredClaimsTests(TestCase):
    """The sweep the cache used to do for free, now that claims are rows."""

    def test_expired_claims_go_and_live_ones_stay(self):
        catalog._claim('tracks', 'fresh')
        catalog._claim('tracks', 'ancient')
        SearchEnrichment.objects.filter(norm_query='ancient').update(
            enriched_at=timezone.now() - timedelta(seconds=catalog.ENRICH_DEDUP_TTL + 60)
        )

        self.assertEqual(catalog.purge_expired_claims(), 1)
        self.assertEqual(
            list(SearchEnrichment.objects.values_list('norm_query', flat=True)),
            ['fresh'],
        )

    def test_purge_is_safe_on_an_empty_table(self):
        self.assertEqual(catalog.purge_expired_claims(), 0)
