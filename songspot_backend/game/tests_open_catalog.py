"""
End-to-end tests for the open catalogue.

Deezer is mocked throughout: these assert our rules, not Deezer's uptime.
"""

from unittest.mock import patch

from django.conf import settings
from django.core.cache import cache, caches
from django.test import TestCase, override_settings
from django.urls import reverse

from game.models import Artist, CatalogSetting, Playlist, PlaylistTrack, Track
from game.services import DeezerService, cache_utils, catalog, deezer_http, rounds


def make_track(title, artist, *, deezer_id, rank=500_000, artist_id=4050205, **kwargs):
    return Track.objects.create(
        title=title,
        artist=artist,
        has_preview=True,
        deezer_id=deezer_id,
        deezer_artist_id=artist_id,
        rank=rank,
        **kwargs,
    )


class CatalogTestCase(TestCase):
    def setUp(self):
        self._reset_caches()

    def tearDown(self):
        self._reset_caches()

    @staticmethod
    def _reset_caches():
        """
        Clear every alias, not just `default`.

        Deezer responses, preview pools and the enrichment claims all live
        under the `deezer` alias, which `cache.clear()` does not touch. Leaving
        it behind makes tests pass or fail on execution order: a preview pool
        warmed by one test is still there for the next one, which then asserts
        against a container it never fetched.

        CatalogSetting is cached twice over — in the shared cache and in a
        process-local memo no cache clear can reach — so it gets its own reset.
        """
        for alias in caches:
            caches[alias].clear()
        CatalogSetting.clear_cache()


class NormalisedColumnsTests(CatalogTestCase):
    def test_save_maintains_the_identity_columns(self):
        track = make_track('Blinding Lights (Live)', 'The Weeknd', deezer_id=1)
        self.assertEqual(track.norm_title, 'blinding lights')
        self.assertEqual(track.norm_artist, 'weeknd')

    def test_renaming_a_track_updates_its_identity(self):
        track = make_track('Wrong Title', 'The Weeknd', deezer_id=2)
        track.title = 'Blinding Lights'
        track.save(update_fields=['title'])
        track.refresh_from_db()
        self.assertEqual(track.norm_title, 'blinding lights')


class CheckGuessTests(CatalogTestCase):
    def setUp(self):
        super().setUp()
        self.answer = make_track('Blinding Lights', 'The Weeknd', deezer_id=908604612)
        self.remix = make_track(
            'Blinding Lights (Major Lazer Remix)', 'The Weeknd', deezer_id=1078622722,
        )
        self.other_song = make_track('Save Your Tears', 'The Weeknd', deezer_id=111)
        self.other_artist = make_track(
            'Blinding Lights', 'Victoria Voss', deezer_id=851937072, artist_id=999,
        )

    def test_a_different_release_of_the_same_song_is_accepted(self):
        self.assertTrue(catalog.check_guess(self.answer, guess_track_id=str(self.remix.id)))

    def test_the_exact_track_is_accepted(self):
        self.assertTrue(catalog.check_guess(self.answer, guess_track_id=str(self.answer.id)))

    def test_a_different_song_is_rejected(self):
        self.assertFalse(catalog.check_guess(self.answer, guess_track_id=str(self.other_song.id)))

    def test_a_cover_by_another_act_is_rejected(self):
        # The line between the two rules: a different *release* of the song is
        # the same answer, a different *artist* is not. The autocomplete prints
        # the artist on every row and keeps distinct artists as distinct rows,
        # so picking the cover is choosing a different recording, not a
        # near-miss on the same one.
        self.assertFalse(
            catalog.check_guess(self.answer, guess_track_id=str(self.other_artist.id))
        )

    def test_a_guess_by_deezer_id_works(self):
        self.assertTrue(catalog.check_guess(self.answer, guess_deezer_id=1078622722))

    def test_a_guess_by_raw_title_works_when_nothing_is_stored(self):
        self.assertTrue(catalog.check_guess(
            self.answer, guess_title='Blinding Lights', guess_artist='The Weeknd',
        ))

    def test_an_empty_guess_is_rejected(self):
        self.assertFalse(catalog.check_guess(self.answer))


class RoundTokenTests(CatalogTestCase):
    def test_round_trip(self):
        token = rounds.issue('abc-123', directed=True)
        payload = rounds.resolve(token)
        self.assertEqual(payload['t'], 'abc-123')
        self.assertTrue(payload['a'])

    def test_a_tampered_token_is_rejected(self):
        token = rounds.issue('abc-123')
        with self.assertRaises(rounds.InvalidRoundToken):
            rounds.resolve(token[:-4] + 'zzzz')

    def test_an_empty_token_is_rejected(self):
        with self.assertRaises(rounds.InvalidRoundToken):
            rounds.resolve('')

    def test_an_expired_token_is_rejected(self):
        token = rounds.issue('abc-123')
        with patch.object(rounds, 'MAX_AGE_SECONDS', -1):
            with self.assertRaises(rounds.InvalidRoundToken):
                rounds.resolve(token)


class PlayableFilterTests(CatalogTestCase):
    def setUp(self):
        super().setUp()
        CatalogSetting.objects.create(min_track_rank=200_000, min_artist_fans=50_000)
        self.popular = make_track('Hit', 'Big Act', deezer_id=1, rank=900_000, artist_id=10)
        self.obscure = make_track('Deep Cut', 'Tiny Act', deezer_id=2, rank=100, artist_id=20)
        Artist.objects.create(deezer_id=10, name='Big Act', nb_fan=5_000_000)
        Artist.objects.create(deezer_id=20, name='Tiny Act', nb_fan=200)

    def test_undirected_picks_apply_the_rank_floor(self):
        playable = catalog.playable(Track.objects.all(), directed=False)
        self.assertIn(self.popular, playable)
        self.assertNotIn(self.obscure, playable)

    def test_a_directed_pick_ignores_every_threshold(self):
        # The whole point: someone who asks for a 200-fan artist gets them.
        playable = catalog.playable(Track.objects.all(), directed=True)
        self.assertIn(self.obscure, playable)

    def test_a_track_without_audio_is_never_playable(self):
        Track.objects.filter(id=self.popular.id).update(has_preview=False)
        self.assertNotIn(
            self.popular, catalog.playable(Track.objects.all(), directed=True),
        )

    def test_curated_tracks_bypass_the_popularity_floor(self):
        # Provenance beats thresholds. A track from Deezer's own "Top J-Pop"
        # playlist is a hit in its market even at a fraction of the follower
        # count a European act would have.
        curated = make_track(
            'J-pop hit', 'Niche Act', deezer_id=4, rank=40_000, artist_id=40,
        )
        Track.objects.filter(id=curated.id).update(is_curated=True)
        Artist.objects.create(deezer_id=40, name='Niche Act', nb_fan=7_879)
        self.assertIn(curated, catalog.playable(Track.objects.all(), directed=False))

    def test_a_curated_source_skips_the_import_time_floors(self):
        info = {
            'title': 'J-pop hit', 'artist': 'Niche Act',
            'preview_url': 'https://example.com/a.mp3',
            'deezer_id': 55, 'deezer_artist_id': 40, 'rank': 40_000,
        }
        artist = Artist.objects.create(deezer_id=40, name='Niche Act', nb_fan=7_879)
        self.assertFalse(catalog.is_playable_payload(info, artist, directed=False))
        self.assertTrue(
            catalog.is_playable_payload(info, artist, directed=False, curated=True)
        )

    def test_a_curated_source_still_rejects_karaoke_and_variants(self):
        # Curation buys a pass on popularity, not on everything.
        artist = Artist.objects.create(deezer_id=41, name='Karaoke Kings', nb_fan=9_000_000)
        base = {
            'preview_url': 'https://example.com/a.mp3',
            'deezer_id': 56, 'deezer_artist_id': 41, 'rank': 900_000,
        }
        self.assertFalse(catalog.is_playable_payload(
            {**base, 'title': 'Hit', 'artist': 'Karaoke Kings'},
            artist, directed=False, curated=True,
        ))
        self.assertFalse(catalog.is_playable_payload(
            {**base, 'title': 'Hit (Live)', 'artist': 'Real Act'},
            None, directed=False, curated=True,
        ))

    def test_junk_artists_are_excluded_from_undirected_picks_only(self):
        Artist.objects.create(deezer_id=30, name='Karaoke Kings', nb_fan=1_000_000)
        junk = make_track('Hit', 'Karaoke Kings', deezer_id=3, rank=900_000, artist_id=30)
        self.assertNotIn(junk, catalog.playable(Track.objects.all(), directed=False))
        self.assertIn(junk, catalog.playable(Track.objects.all(), directed=True))


class CacheResilienceTests(CatalogTestCase):
    """
    Losing Redis must cost speed and Deezer quota — never availability.

    An earlier version pointed Django's `default` cache at Redis, which put
    DRF's throttling on it; throttling calls the cache directly and raises, so
    every game endpoint answered 500 the moment Redis went away. The catalogue
    cache now lives on its own alias, and every access to it is wrapped.
    """

    def setUp(self):
        super().setUp()
        cache_utils.reset_breaker()

    def tearDown(self):
        cache_utils.reset_breaker()
        super().tearDown()

    def test_djangos_default_cache_is_never_the_redis_one(self):
        # DRF throttling, sessions and anything else reaching for `default`
        # must not be able to fail because Redis is down.
        self.assertIn('locmem', settings.CACHES['default']['BACKEND'])

    def test_a_read_failure_reads_as_a_miss(self):
        with patch.object(cache_utils, '_cache', side_effect=RuntimeError('redis down')):
            self.assertIsNone(cache_utils.cache_get('anything'))

    def test_a_write_failure_falls_through_to_the_local_cache(self):
        with patch.object(cache_utils, 'caches', _BrokenSharedCache()):
            self.assertTrue(cache_utils.cache_set('k', 'v', timeout=60))
            self.assertEqual(cache_utils.cache_get('k'), 'v')

    def test_the_breaker_stops_paying_the_timeout_on_every_call(self):
        # Each attempt on a dead Redis costs a connect timeout, so a page
        # needing a dozen reads would take a dozen seconds. After the threshold
        # the shared cache must stop being touched at all.
        broken = _BrokenSharedCache()
        with patch.object(cache_utils, 'caches', broken):
            for _ in range(20):
                cache_utils.cache_get('k')
        self.assertLessEqual(broken.shared_attempts, cache_utils._BREAKER_THRESHOLD)

    def test_the_breaker_lets_traffic_through_again_after_the_cooldown(self):
        with patch.object(cache_utils, '_cache', side_effect=RuntimeError('redis down')):
            for _ in range(cache_utils._BREAKER_THRESHOLD):
                cache_utils.cache_get('k')
        cache_utils.reset_breaker()
        cache_utils.cache_set('k', 'recovered')
        self.assertEqual(cache_utils.cache_get('k'), 'recovered')

    def test_a_round_is_still_served_with_the_cache_down(self):
        make_track('Hit', 'Big Act', deezer_id=1, rank=900_000)
        with patch.object(cache_utils, '_cache', side_effect=RuntimeError('redis down')):
            response = self.client.get(reverse('game:next_song'), {'v': 2})
        self.assertEqual(response.status_code, 200)


class RateLimiterTests(CatalogTestCase):
    """
    The Deezer limiter must not fail open.

    Regression: the limiter counted through the shared cache, and when that
    cache became unreachable its counters returned "nothing", which the limiter
    read as "there is room". Pacing silently vanished at the one moment it was
    needed — a bulk import against a dead Redis fired hundreds of unthrottled
    calls, exhausted the quota, and failed every category after the second.
    """

    def setUp(self):
        super().setUp()
        cache_utils.reset_breaker()
        caches[cache_utils.LOCAL_ALIAS].clear()

    def tearDown(self):
        cache_utils.reset_breaker()
        caches[cache_utils.LOCAL_ALIAS].clear()
        super().tearDown()

    def test_it_stops_traffic_once_the_window_is_full(self):
        allowed = sum(
            1 for _ in range(deezer_http.RATE_LIMIT + 20)
            if deezer_http._rate_limit_slot()
        )
        self.assertLessEqual(allowed, deezer_http.RATE_LIMIT)

    def test_it_still_limits_when_the_shared_cache_is_gone(self):
        broken = _BrokenSharedCache()
        with patch.object(cache_utils, 'caches', broken):
            allowed = sum(
                1 for _ in range(deezer_http.RATE_LIMIT + 20)
                if deezer_http._rate_limit_slot()
            )
        self.assertLessEqual(allowed, deezer_http.RATE_LIMIT)
        self.assertGreater(allowed, 0, 'it must not block everything either')

    def test_responses_are_still_cached_when_the_shared_cache_is_gone(self):
        # Degrading to no cache at all would mean re-asking Deezer for
        # everything, which is how the quota got burned in the first place.
        with patch.object(cache_utils, 'caches', _BrokenSharedCache()):
            cache_utils.cache_set('k', 'v', timeout=60)
            self.assertEqual(cache_utils.cache_get('k'), 'v')


class TransientRefusalTests(CatalogTestCase):
    """
    A refused call must be waited out, not written off.

    Deezer counts its per-IP quota its own way, so it can refuse even while we
    are pacing correctly. One refused chart request used to leave a category
    empty for the whole day.
    """

    def test_quota_errors_are_recognised_as_transient(self):
        self.assertTrue(deezer_http._is_transient(
            {'type': 'Exception', 'message': 'Quota limit exceeded', 'code': 4}
        ))
        self.assertTrue(deezer_http._is_transient(
            {'message': 'Service temporarily unavailable'}
        ))

    def test_permanent_errors_are_not_retried(self):
        # Retrying a missing resource just burns the time budget.
        self.assertFalse(deezer_http._is_transient(
            {'type': 'DataException', 'message': 'no data', 'code': 800000}
        ))
        self.assertFalse(deezer_http._is_transient(None))

    def test_a_refusal_is_retried_and_then_succeeds(self):
        http = deezer_http.DeezerHttp(max_wait=10)
        responses = [
            _FakeResponse({'error': {'message': 'Quota limit exceeded', 'code': 4}}),
            _FakeResponse({'data': [{'id': 1}]}),
        ]
        with patch.object(http, '_session') as session, \
                patch.object(deezer_http.time, 'sleep'), \
                patch.object(settings, 'TESTING', False):
            session.get.side_effect = responses
            result = http._fetch('/chart/116/tracks', None)
        self.assertEqual(result, {'data': [{'id': 1}]})
        self.assertEqual(session.get.call_count, 2)

    def test_it_gives_up_once_the_budget_is_spent(self):
        # A web request cannot wait: it has a player on the other end and a
        # database to fall back on.
        http = deezer_http.DeezerHttp(max_wait=0)
        with patch.object(http, '_session') as session, \
                patch.object(settings, 'TESTING', False):
            session.get.return_value = _FakeResponse(
                {'error': {'message': 'Quota limit exceeded', 'code': 4}}
            )
            with self.assertRaises(deezer_http.DeezerUnavailable):
                http._fetch('/chart/116/tracks', None)


class _FakeResponse:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self):
        pass

    def json(self):
        return self._payload


class _BrokenSharedCache:
    """Mapping where the shared alias raises and the local one works."""

    def __init__(self):
        self.shared_attempts = 0

    def __getitem__(self, alias):
        if alias == cache_utils.CACHE_ALIAS:
            self.shared_attempts += 1
            raise RuntimeError('redis down')
        return caches[alias]


class SearchTracksDedupTests(CatalogTestCase):
    def setUp(self):
        super().setUp()
        for i, title in enumerate([
            'Blinding Lights',
            'Blinding Lights (Remix)',
            'Blinding Lights (Live)',
            'Blinding Lights (Major Lazer Remix)',
        ]):
            make_track(title, 'The Weeknd', deezer_id=100 + i, rank=900_000 - i)

    @patch('game.services.catalog.DeezerService')
    def test_one_row_per_song(self, mock_deezer):
        mock_deezer.return_value.search_track.return_value = {'data': []}
        results = catalog.search_tracks('blinding')
        self.assertEqual(len(results), 1)
        # The highest-ranked release represents the group, which is also what
        # NextSongView serves, so the two agree.
        self.assertEqual(results[0].title, 'Blinding Lights')


class SearchByArtistTests(CatalogTestCase):
    """
    The guess box is how a player names a song they only half remember, so it
    has to find "that ROSALÍA song" from the artist alone — and it has to do it
    from what a player actually types, which is `rosalia`, without the accent.
    """

    def setUp(self):
        super().setUp()
        Artist.objects.create(deezer_id=1614102, name='ROSALÍA', nb_fan=3_000_000)
        for i, title in enumerate(['DESPECHÁ', 'LA FAMA', 'BESO']):
            make_track(title, 'ROSALÍA', deezer_id=300 + i,
                       rank=800_000 - i, artist_id=1614102)
        Artist.objects.create(deezer_id=4050205, name='The Weeknd', nb_fan=14_659_544)
        make_track('Blinding Lights', 'The Weeknd', deezer_id=908604612,
                   rank=984_833, artist_id=4050205)

    @patch('game.services.catalog.DeezerService')
    def test_an_artist_name_finds_their_songs(self, mock_deezer):
        mock_deezer.return_value.search_track.return_value = {'data': []}
        results = catalog.search_tracks('rosalia')
        self.assertEqual({t.title for t in results}, {'DESPECHÁ', 'LA FAMA', 'BESO'})

    @patch('game.services.catalog.DeezerService')
    def test_the_accented_spelling_finds_them_too(self, mock_deezer):
        # SQLite's LIKE only case-folds ASCII, so `ROSALÍA` does not match
        # `Rosalía` on a raw column however the player spells it.
        mock_deezer.return_value.search_track.return_value = {'data': []}
        results = catalog.search_tracks('Rosalía')
        self.assertEqual(len(results), 3)

    @patch('game.services.catalog.DeezerService')
    def test_artist_and_title_together_in_either_order(self, mock_deezer):
        mock_deezer.return_value.search_track.return_value = {'data': []}
        for query in ('rosalia despecha', 'despecha rosalia'):
            results = catalog.search_tracks(query)
            self.assertEqual([t.title for t in results], ['DESPECHÁ'], query)

    @patch('game.services.catalog.DeezerService')
    def test_a_leading_the_still_finds_the_act(self, mock_deezer):
        # `normalize_artist` drops it, so `norm_artist` is plain `weeknd`.
        mock_deezer.return_value.search_track.return_value = {'data': []}
        results = catalog.search_tracks('the weeknd')
        self.assertEqual([t.title for t in results], ['Blinding Lights'])

    @patch('game.services.catalog.DeezerService')
    def test_words_from_neither_field_match_nothing(self, mock_deezer):
        mock_deezer.return_value.search_track.return_value = {'data': []}
        self.assertEqual(catalog.search_tracks('rosalia starboy'), [])


class SearchRankingTests(CatalogTestCase):
    """
    The guess list has to put the real song first.

    Deezer ranks a cover of "Blinding Lights" by an unknown singer at 633 257
    against the original's 984 833 — close enough to crowd the list. Since a
    cover by a different artist is judged wrong, a badly ordered list costs the
    player a life for a song they identified correctly.
    """

    def setUp(self):
        super().setUp()
        Artist.objects.create(deezer_id=4050205, name='The Weeknd', nb_fan=14_659_544)
        self.original = make_track(
            'Blinding Lights', 'The Weeknd',
            deezer_id=908604612, rank=984_833, artist_id=4050205,
        )
        # Real rows from the live API, artists we hold no fan count for.
        self.covers = [
            make_track('Blinding Lights (Acoustic Version)', 'Victoria Voss',
                       deezer_id=851937072, rank=633_257, artist_id=901),
            make_track('Blinding Lights', 'Emily Dawn',
                       deezer_id=3638278102, rank=594_628, artist_id=902),
            make_track('Blinding Lights', 'Pablo Cepeda',
                       deezer_id=2177992817, rank=591_569, artist_id=903),
            make_track('Blinding Lights', 'Loi',
                       deezer_id=1486911192, rank=573_433, artist_id=904),
        ]

    @patch('game.services.catalog.DeezerService')
    def test_the_original_comes_first(self, mock_deezer):
        mock_deezer.return_value.search_track.return_value = {'data': []}
        results = catalog.search_tracks('blinding lights')
        self.assertEqual(results[0].artist, 'The Weeknd')

    @patch('game.services.catalog.DeezerService')
    def test_covers_do_not_fill_the_whole_list(self, mock_deezer):
        mock_deezer.return_value.search_track.return_value = {'data': []}
        results = catalog.search_tracks('blinding lights')
        self.assertLessEqual(len(results), catalog.MAX_ARTISTS_PER_TITLE)

    @patch('game.services.catalog.DeezerService')
    def test_distinct_songs_sharing_a_title_all_survive_the_cap(self, mock_deezer):
        # Three famous, genuinely different songs called "Hello". The cap must
        # not be so tight that it hides one of them.
        mock_deezer.return_value.search_track.return_value = {'data': []}
        for i, (artist, artist_id) in enumerate([
            ('Adele', 801), ('Lionel Richie', 802), ('Martin Solveig', 803),
        ]):
            Artist.objects.create(deezer_id=artist_id, name=artist, nb_fan=1_000_000 - i)
            make_track('Hello', artist, deezer_id=700 + i, rank=800_000 - i,
                       artist_id=artist_id)
        results = catalog.search_tracks('hello')
        self.assertEqual(
            {t.artist for t in results},
            {'Adele', 'Lionel Richie', 'Martin Solveig'},
        )

    @patch('game.services.catalog.DeezerService')
    def test_karaoke_acts_sort_last(self, mock_deezer):
        mock_deezer.return_value.search_track.return_value = {'data': []}
        Artist.objects.create(deezer_id=905, name='Karaoke Kings', nb_fan=9_000_000)
        make_track('Blinding Lights', 'Karaoke Kings',
                   deezer_id=999, rank=999_999, artist_id=905)
        results = catalog.search_tracks('blinding lights')
        self.assertEqual(results[0].artist, 'The Weeknd')
        self.assertNotIn('Karaoke Kings', [t.artist for t in results[:1]])


@override_settings(REST_FRAMEWORK={
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ),
    'DEFAULT_PERMISSION_CLASSES': ('rest_framework.permissions.AllowAny',),
    'DEFAULT_THROTTLE_RATES': {},
})
class NextSongAndGuessApiTests(CatalogTestCase):
    def setUp(self):
        super().setUp()
        CatalogSetting.objects.create(min_track_rank=1_000)
        self.answer = make_track('Blinding Lights', 'The Weeknd', deezer_id=908604612)
        self.remix = make_track(
            'Blinding Lights (Major Lazer Remix)', 'The Weeknd',
            deezer_id=1078622722, rank=400_000,
        )

    def test_v2_round_withholds_the_answer(self):
        response = self.client.get(reverse('game:next_song'), {'v': 2})
        self.assertEqual(response.status_code, 200)
        self.assertIn('round_token', response.data)
        self.assertIn('preview_url', response.data)
        # The answer used to ride along with the audio.
        self.assertNotIn('title', response.data)
        self.assertNotIn('artist', response.data)

    def test_v1_round_still_carries_the_answer(self):
        # Already-installed apps judge the guess themselves and break without it.
        response = self.client.get(reverse('game:next_song'))
        self.assertEqual(response.status_code, 200)
        self.assertIn('title', response.data)
        self.assertNotIn('round_token', response.data)

    def test_next_song_serves_the_canonical_release(self):
        # Both rows are the same song; the higher-ranked one is what the
        # autocomplete offers, so it is what the round must use.
        for _ in range(5):
            response = self.client.get(reverse('game:next_song'), {'v': 2})
            self.assertEqual(response.data['id'], str(self.answer.id))

    def test_guessing_another_release_is_correct(self):
        token = rounds.issue(str(self.answer.id))
        response = self.client.post(reverse('game:guess'), {
            'round_token': token,
            'guess_track_id': str(self.remix.id),
        })
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data['correct'])
        self.assertEqual(response.data['answer']['title'], 'Blinding Lights')

    def test_giving_up_returns_the_answer_without_scoring_it(self):
        token = rounds.issue(str(self.answer.id))
        response = self.client.post(reverse('game:guess'), {'round_token': token})
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.data['correct'])
        self.assertTrue(response.data['gave_up'])
        self.assertEqual(response.data['answer']['title'], 'Blinding Lights')

    def test_a_forged_token_is_refused(self):
        response = self.client.post(reverse('game:guess'), {
            'round_token': 'not-a-real-token',
            'guess_track_id': str(self.remix.id),
        })
        self.assertEqual(response.status_code, 400)

    def test_an_empty_pool_reports_404_rather_than_a_wrong_answer(self):
        Track.objects.all().delete()
        response = self.client.get(reverse('game:next_song'), {'v': 2})
        self.assertEqual(response.status_code, 404)


@override_settings(REST_FRAMEWORK={
    'DEFAULT_AUTHENTICATION_CLASSES': (),
    'DEFAULT_PERMISSION_CLASSES': ('rest_framework.permissions.AllowAny',),
    'DEFAULT_THROTTLE_RATES': {},
})
class DirectedArtistPlayTests(CatalogTestCase):
    """A player who names an artist gets that artist, thresholds notwithstanding."""

    def setUp(self):
        super().setUp()
        CatalogSetting.objects.create(min_track_rank=500_000, min_artist_fans=1_000_000)
        Artist.objects.create(deezer_id=777, name='Tiny Local Act', nb_fan=212)
        self.obscure = make_track(
            'Deep Cut', 'Tiny Local Act', deezer_id=5, rank=90, artist_id=777,
        )

    @patch('game.services.catalog.ensure_artist_tracks')
    def test_an_artist_far_below_the_floor_is_playable(self, mock_ensure):
        mock_ensure.return_value = [self.obscure]
        response = self.client.get(
            reverse('game:next_song'), {'v': 2, 'artist_id': 777},
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['id'], str(self.obscure.id))
        # The app needs this to warn "only 1 track available" up front instead
        # of ending the session on a confusing "pool cleared".
        self.assertEqual(response.data['pool_size'], 1)

    def test_a_non_numeric_artist_id_is_a_bad_request(self):
        response = self.client.get(
            reverse('game:next_song'), {'v': 2, 'artist_id': 'the-weeknd'},
        )
        self.assertEqual(response.status_code, 400)


class UpsertTrackTests(CatalogTestCase):
    def test_reimporting_the_same_deezer_track_updates_rather_than_duplicates(self):
        info = {
            'title': 'Blinding Lights',
            'artist': 'The Weeknd',
            'preview_url': 'https://example.com/a.mp3',
            'deezer_id': 908604612,
            'deezer_artist_id': 4050205,
            'rank': 900_000,
        }
        first = catalog.upsert_track(info)
        second = catalog.upsert_track({**info, 'cover_url': 'https://example.com/c.jpg'})
        self.assertEqual(first.id, second.id)
        self.assertEqual(Track.objects.count(), 1)
        self.assertEqual(second.cover_url, 'https://example.com/c.jpg')

    def test_a_payload_without_audio_is_not_stored(self):
        self.assertIsNone(catalog.upsert_track({
            'title': 'Silent', 'artist': 'Nobody', 'preview_url': '',
        }))
        self.assertEqual(Track.objects.count(), 0)

    def test_distinct_releases_of_one_song_stay_distinct_rows(self):
        # Regression: an earlier version matched on the normalised identity for
        # every import, so the live take was merged into the studio row — and
        # because a newer preview always wins, the row titled "Blinding Lights"
        # ended up playing live audio.
        base = {
            'artist': 'The Weeknd',
            'deezer_artist_id': 4050205,
        }
        studio = catalog.upsert_track({
            **base, 'title': 'Blinding Lights', 'deezer_id': 908604612,
            'preview_url': 'https://example.com/studio.mp3',
        })
        live = catalog.upsert_track({
            **base, 'title': 'Blinding Lights (Live)', 'deezer_id': 2166259437,
            'preview_url': 'https://example.com/live.mp3',
        })
        self.assertNotEqual(studio.id, live.id)
        studio.refresh_from_db()
        self.assertTrue(studio.has_preview)
        # Separate rows, but still the same answer.
        self.assertTrue(catalog.check_guess(studio, guess_track_id=str(live.id)))

    def test_a_legacy_row_without_a_deezer_id_is_adopted(self):
        # The seeded catalogue predates the ID column; re-importing one of
        # those songs should fill the row in, not duplicate it.
        legacy = Track.objects.create(
            title='Blinding Lights',
            artist='The Weeknd',
            has_preview=True,
        )
        adopted = catalog.upsert_track({
            'title': 'Blinding Lights', 'artist': 'The Weeknd',
            'deezer_id': 908604612, 'deezer_artist_id': 4050205,
            'preview_url': 'https://example.com/fresh.mp3',
        })
        self.assertEqual(adopted.id, legacy.id)
        self.assertEqual(adopted.deezer_id, 908604612)
        self.assertEqual(Track.objects.count(), 1)

    def test_audio_is_recorded_as_a_flag_not_a_url(self):
        """
        The URL is never stored; only the fact that Deezer had one.

        A preview URL is signed for fifteen minutes, so a column holding one is
        expired every time it is read. `has_preview` is what survives, and it
        is what `playable()` filters on.
        """
        info = {
            'title': 'Blinding Lights', 'artist': 'The Weeknd',
            'preview_url': 'https://example.com/old.mp3', 'deezer_id': 1,
        }
        track = catalog.upsert_track(info)
        self.assertTrue(track.has_preview)
        self.assertFalse(hasattr(track, 'preview_url'))

    def test_a_legacy_row_without_audio_gains_the_flag_on_re_import(self):
        legacy = Track.objects.create(
            title='Silent Row', artist='Old Act', deezer_id=42, has_preview=False,
        )
        catalog.upsert_track({
            'title': 'Silent Row', 'artist': 'Old Act', 'deezer_id': 42,
            'preview_url': 'https://example.com/found.mp3',
        })
        legacy.refresh_from_db()
        self.assertTrue(legacy.has_preview)


class ArtistSearchRankingTests(CatalogTestCase):
    @patch('game.services.catalog.DeezerService')
    def test_results_are_ranked_by_followers_not_by_deezer_order(self, mock_deezer):
        # Deezer's real ordering for `q=weeknd`: the 2k-fan namesake first.
        mock_deezer.return_value.search_artists.return_value = [
            {'id': 11005292, 'name': 'Weeknd', 'nb_fan': 2101},
            {'id': 4050205, 'name': 'The Weeknd', 'nb_fan': 14659544},
            {'id': 188197757, 'name': 'The Retro Weeknd', 'nb_fan': 64},
        ]
        results = catalog.search_artists('weeknd')
        self.assertEqual(results[0].name, 'The Weeknd')

    @patch('game.services.catalog.DeezerService')
    def test_cover_acts_rank_last_but_stay_findable(self, mock_deezer):
        mock_deezer.return_value.search_artists.return_value = [
            {'id': 1, 'name': 'Karaoke Kings', 'nb_fan': 9_000_000},
            {'id': 2, 'name': 'Real Band', 'nb_fan': 1_000},
        ]
        results = catalog.search_artists('band')
        self.assertEqual(results[0].name, 'Real Band')
        self.assertEqual(results[-1].name, 'Karaoke Kings')


class ArtistArtworkTests(CatalogTestCase):
    """
    Walking one artist must not put their face on anyone else's row.

    Album track payloads carry an artist object with an id and a name but no
    picture, so the walk grafts the artist's own artwork onto the payloads it
    collects. A track credited to a feature keeps its own `deezer_artist_id`,
    and grafting unconditionally created that artist wearing the walked
    artist's photo — one picture reached fifteen artists in production.
    """

    ANGELE = 'https://cdn-images.dzcdn.net/images/artist/0f9/1000x1000.jpg'

    @staticmethod
    def _payload(deezer_id, title, artist):
        """An album track payload: an artist object, with no picture in it."""
        return {
            'id': deezer_id,
            'title': title,
            'preview': f'https://example.com/{deezer_id}.mp3',
            'rank': 800_000,
            'artist': artist,
            'album': {'title': 'Nonante-Cinq', 'cover_xl': 'https://x/c.jpg'},
        }

    def _walk(self, payloads):
        deezer = DeezerService()
        with patch.object(
            DeezerService, 'get_artist_top_tracks', return_value=payloads,
        ):
            catalog._import_artist_top(deezer, 1042268, self.ANGELE)

    def test_the_walked_artist_keeps_their_own_artwork(self):
        self._walk([self._payload(
            1, 'Bruxelles je t aime', {'id': 1042268, 'name': 'Angèle'},
        )])

        self.assertEqual(
            Artist.objects.get(deezer_id=1042268).picture_url, self.ANGELE,
        )

    def test_a_feature_on_the_walk_is_not_given_that_artwork(self):
        self._walk([
            self._payload(1, 'Bruxelles je t aime', {'id': 1042268, 'name': 'Angèle'}),
            self._payload(2, 'Démons', {'id': 9197980, 'name': 'Damso'}),
        ])

        damso = Artist.objects.get(deezer_id=9197980)
        self.assertEqual(damso.name, 'Damso')
        # Better no face than the wrong one: `backfill_artist_pictures` fetches
        # this by ID later, which cannot pick the wrong artist.
        self.assertIsNone(damso.picture_url)

    def test_a_payload_crediting_nobody_still_gets_the_artwork(self):
        # No id in the payload means the row is attributed to the artist being
        # walked, so the artwork is theirs to give.
        self._walk([self._payload(3, 'Balance ton quoi', {'name': 'Angèle'})])

        self.assertEqual(
            Artist.objects.get(deezer_id=1042268).picture_url, self.ANGELE,
        )
