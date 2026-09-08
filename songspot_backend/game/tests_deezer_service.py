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


class DeezerServiceMetadataTests(SimpleTestCase):
    @patch.object(DeezerService, 'get_album')
    @patch.object(DeezerService, 'get_track')
    def test_enrich_track_info_uses_full_track_and_album_metadata(
        self,
        mock_get_track,
        mock_get_album,
    ):
        service = DeezerService()
        raw_track = {
            'id': 42,
            'title': 'Song 42',
            'preview': 'https://example.com/preview.mp3',
            'artist': {'name': 'Artist 42'},
            'album': {'id': 7},
        }
        mock_get_track.return_value = {
            'id': 42,
            'title': 'Song 42',
            'preview': 'https://example.com/preview.mp3',
            'artist': {'name': 'Artist 42'},
            'album': {'id': 7, 'title': 'Album 7'},
        }
        mock_get_album.return_value = {
            'id': 7,
            'release_date': '1998-09-15',
            'genres': {'data': [{'id': 152, 'name': 'Rock'}]},
            'cover_xl': 'https://example.com/cover-xl.jpg',
        }

        info = service.enrich_track_info(raw_track)

        self.assertEqual(info['release_year'], 1998)
        self.assertEqual(info['genre'], 'Rock')
        self.assertEqual(info['cover_url'], 'https://example.com/cover-xl.jpg')


class DeezerServiceFieldWidthTests(SimpleTestCase):
    """A Deezer payload has to fit the columns in game.models.Track."""

    def test_overlong_title_and_artist_are_truncated(self):
        service = DeezerService()

        info = service.extract_track_info({
            'id': 99,
            'title': 'T' * 400,
            'preview': 'https://example.com/99.mp3',
            'artist': {'name': 'A' * 400},
        })

        # 255 is Track.title / Track.artist. Left whole, one of these raises
        # DataError inside bulk_create and loses the other 199 rows with it.
        self.assertEqual(len(info['title']), 255)
        self.assertEqual(len(info['artist']), 255)

    def test_ordinary_title_and_artist_are_untouched(self):
        service = DeezerService()

        info = service.extract_track_info({
            'id': 100,
            'title': 'Song 100',
            'preview': 'https://example.com/100.mp3',
            'artist': {'name': 'Artist 100'},
        })

        self.assertEqual(info['title'], 'Song 100')
        self.assertEqual(info['artist'], 'Artist 100')
        self.assertIsNone(info['genre'])
