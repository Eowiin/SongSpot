from datetime import timedelta
from unittest.mock import patch

from django.utils import timezone

from game.models import Artist, CatalogSetting, Track
from game.services import catalog
from game.services.matching import normalize_artist, normalize_title
from game.tests_open_catalog import CatalogTestCase, make_track


def payload(ident, title='Track'):
    return {
        'id': ident, 'title': title, 'preview': 'https://example.test/preview.mp3',
        'artist': {'id': 12, 'name': 'Small Artist'}, 'album': {}, 'rank': 100,
    }


class DirectedRefreshTests(CatalogTestCase):
    @patch('game.services.catalog.DeezerService')
    def test_fresh_small_catalogue_does_not_reimport(self, service):
        Artist.objects.create(deezer_id=12, name='Small Artist', directed_refreshed_at=timezone.now())
        track = make_track('Only Song', 'Small Artist', deezer_id=1, artist_id=12)
        self.assertEqual(catalog.ensure_artist_tracks(12), [track])
        self.assertFalse(service.return_value.get_artist_top_tracks.called)
        self.assertFalse(service.return_value.get_artist_albums.called)

    def test_empty_catalogue_retries_after_a_provider_outage(self):
        Artist.objects.create(deezer_id=12, name='Small Artist', directed_refreshed_at=timezone.now())
        with patch.object(catalog, '_import_artist_top', return_value=[]) as top, \
             patch.object(catalog, '_import_artist_albums', return_value=[]):
            catalog.ensure_artist_tracks(12)
        top.assert_called_once()

    def test_expired_small_catalogue_refreshes_again(self):
        days = CatalogSetting.get_solo().artist_top_ttl_days
        Artist.objects.create(deezer_id=12, name='Small Artist',
                              top_refreshed_at=timezone.now()-timedelta(days=days+1))
        with patch.object(catalog, '_import_artist_top', return_value=[]) as top, \
             patch.object(catalog, '_import_artist_albums', return_value=[]):
            catalog.ensure_artist_tracks(12)
        top.assert_called_once()
        self.assertGreater(Artist.objects.get(pk=12).top_refreshed_at,
                           timezone.now()-timedelta(minutes=1))

    def test_background_top_refresh_does_not_skip_album_discovery(self):
        Artist.objects.create(deezer_id=12, name='Small Artist', top_refreshed_at=timezone.now())
        make_track('Only Song', 'Small Artist', deezer_id=1, artist_id=12)
        with patch.object(catalog, '_import_artist_top', return_value=[]) as top, \
             patch.object(catalog, '_import_artist_albums', return_value=[]) as albums:
            catalog.ensure_artist_tracks(12)
        top.assert_called_once()
        albums.assert_called_once()
        self.assertIsNotNone(Artist.objects.get(pk=12).directed_refreshed_at)

    def test_album_pages_are_persisted_in_one_batch(self):
        from game.services.deezer_service import DeezerService
        service = DeezerService()
        Artist.objects.create(deezer_id=12, name='Small Artist')
        with patch.object(service, 'get_artist_albums', return_value=[
            {'id': 1, 'cover_xl': 'https://example.test/cover.jpg'}, {'id': 2}, {'id': 3},
        ]), patch.object(service, 'get_album_tracks', side_effect=[
            [payload(1)], [payload(1)], [payload(2)],
        ]) as pages, patch.object(catalog, 'bulk_upsert_tracks', wraps=catalog.bulk_upsert_tracks) as persist:
            tracks = catalog._import_artist_albums(service, 12, None, wanted=2, already=[])
        self.assertEqual(pages.call_count, 3)  # duplicate release ID does not satisfy the target
        self.assertEqual(persist.call_count, 1)
        self.assertEqual({t.deezer_id for t in tracks}, {1, 2})


class ExpandedCreditsTests(CatalogTestCase):
    def test_valid_credit_can_expand_beyond_255_characters(self):
        name = ('A & B ' * 42).strip()
        self.assertLessEqual(len(name), 255)
        self.assertGreater(len(normalize_artist(name)), 255)
        artist = catalog.upsert_artist({'id': 12, 'name': name})
        artist.refresh_from_db()
        self.assertEqual(artist.norm_name, normalize_artist(name))
        tracks = catalog.upsert_tracks([{
            **payload(1, title=name), 'artist': {'id': 12, 'name': name},
        }])
        track = Track.objects.get(pk=tracks[0].pk)
        self.assertEqual(track.norm_artist, normalize_artist(name))
        self.assertEqual(track.norm_title, normalize_title(name))


class SearchCandidateTests(CatalogTestCase):
    def test_normalized_search_keeps_accents_qualifiers_and_cross_field_matches(self):
        track = make_track('Été (Live at Paris)', 'Simon & Garfunkel', deezer_id=1)
        for query in ['ete', 'live paris', 'simon and garfunkel', 'paris garfunkel']:
            with self.subTest(query=query):
                self.assertIn(track, catalog._candidates(catalog._query_filter(query), query))
