from unittest.mock import patch

from django.test import SimpleTestCase

from game.services import DeezerService


def _build_track(track_id: int, *, with_preview: bool = True) -> dict:
    return {
        'id': track_id,
        'title': f'Song {track_id}',
        'preview': f'https://example.com/{track_id}.mp3' if with_preview else '',
        'artist': {'name': f'Artist {track_id}'},
    }


class DeezerServiceRandomTracksTests(SimpleTestCase):
    @patch.object(DeezerService, 'get_artist_top_tracks')
    @patch.object(DeezerService, 'get_top_artists')
    @patch.object(DeezerService, 'get_chart_tracks')
    @patch.object(DeezerService, 'get_random_tracks_from_genre')
    def test_get_random_tracks_can_return_more_than_80(
        self,
        mock_get_random_tracks_from_genre,
        mock_get_chart_tracks,
        mock_get_top_artists,
        mock_get_artist_top_tracks,
    ):
        service = DeezerService()

        # Same 10 tracks from every genre call to force de-duplication.
        mock_get_random_tracks_from_genre.return_value = [
            _build_track(track_id) for track_id in range(1, 11)
        ]
        mock_get_chart_tracks.return_value = [
            _build_track(track_id) for track_id in range(11, 61)
        ]
        mock_get_top_artists.return_value = [{'id': artist_id} for artist_id in range(1, 300)]

        def artist_tracks_side_effect(artist_id: int, limit: int = 3):
            start = 1000 + (artist_id * 10)
            return [_build_track(start + idx) for idx in range(limit)]

        mock_get_artist_top_tracks.side_effect = artist_tracks_side_effect

        tracks = service.get_random_tracks(count=200)

        self.assertEqual(len(tracks), 200)
        self.assertEqual(len({track['id'] for track in tracks}), 200)

    @patch.object(DeezerService, 'get_artist_top_tracks', return_value=[])
    @patch.object(DeezerService, 'get_top_artists', return_value=[])
    @patch.object(DeezerService, 'get_chart_tracks')
    @patch.object(DeezerService, 'get_random_tracks_from_genre')
    def test_get_random_tracks_filters_missing_preview_and_duplicates(
        self,
        mock_get_random_tracks_from_genre,
        mock_get_chart_tracks,
        _mock_get_top_artists,
        _mock_get_artist_top_tracks,
    ):
        service = DeezerService()

        mock_get_random_tracks_from_genre.return_value = [
            _build_track(1),
            _build_track(1),  # Duplicate ID
            _build_track(2, with_preview=False),  # Missing preview
            _build_track(3),
        ]
        mock_get_chart_tracks.return_value = []

        tracks = service.get_random_tracks(count=10)

        self.assertEqual({track['id'] for track in tracks}, {1, 3})

    def test_get_random_tracks_returns_empty_for_non_positive_count(self):
        service = DeezerService()
        self.assertEqual(service.get_random_tracks(count=0), [])
        self.assertEqual(service.get_random_tracks(count=-5), [])
