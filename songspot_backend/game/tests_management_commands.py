from io import StringIO
from unittest.mock import patch

from django.core.management import call_command
from django.test import TestCase

from .models import Track


class UpdateTrackMetadataCommandTests(TestCase):
    @patch('game.management.commands.update_track_metadata.DeezerService.enrich_track_info')
    @patch('game.management.commands.update_track_metadata.DeezerService.get_track')
    def test_backfills_missing_metadata_from_existing_deezer_id(
        self,
        mock_get_track,
        mock_enrich_track_info,
    ):
        track = Track.objects.create(
            title='Existing Song',
            artist='Existing Artist',
            preview_url='https://example.com/preview.mp3',
            deezer_id=123,
        )
        raw_track = {'id': 123}
        mock_get_track.return_value = raw_track
        mock_enrich_track_info.return_value = {
            'deezer_id': 123,
            'cover_url': 'https://example.com/cover.jpg',
            'release_year': 1999,
            'genre': 'Rock',
        }

        call_command('update_track_metadata', stdout=StringIO())

        track.refresh_from_db()
        self.assertEqual(track.cover_url, 'https://example.com/cover.jpg')
        self.assertEqual(track.release_year, 1999)
        self.assertEqual(track.genre, 'Rock')

    @patch('game.management.commands.update_track_metadata.DeezerService.enrich_track_info')
    @patch('game.management.commands.update_track_metadata.DeezerService.search_track')
    def test_search_missing_can_attach_deezer_id_for_existing_track(
        self,
        mock_search_track,
        mock_enrich_track_info,
    ):
        track = Track.objects.create(
            title='Search Song',
            artist='Search Artist',
            preview_url='https://example.com/preview.mp3',
        )
        candidate = {
            'id': 456,
            'title': 'Search Song',
            'artist': {'name': 'Search Artist'},
        }
        mock_search_track.return_value = {'data': [candidate]}
        mock_enrich_track_info.return_value = {
            'deezer_id': 456,
            'cover_url': 'https://example.com/search-cover.jpg',
            'release_year': 2004,
            'genre': 'Pop',
        }

        call_command('update_track_metadata', '--search-missing', stdout=StringIO())

        track.refresh_from_db()
        self.assertEqual(track.deezer_id, 456)
        self.assertEqual(track.cover_url, 'https://example.com/search-cover.jpg')
        self.assertEqual(track.release_year, 2004)
        self.assertEqual(track.genre, 'Pop')
