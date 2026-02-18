import requests
import random
from typing import Optional, Dict, List
from django.conf import settings


class DeezerService:
    """
    Service to interact with Deezer API.
    Fetches random tracks and provides track information.
    """
    BASE_URL = "https://api.deezer.com"

    # Popular genres and their Deezer IDs for random selection
    GENRE_IDS = [
        132,  # Pop
        116,  # Rap/Hip Hop
        152,  # Rock
        113,  # Dance
        165,  # R&B
        129,  # Jazz
        85,   # Alternative
        106,  # Electro
        464,  # Indie Pop
    ]

    def _collect_unique_preview_tracks(
        self,
        destination: List[Dict],
        candidates: List[Dict],
        seen_ids: set[int],
    ) -> None:
        """Append previewable tracks while avoiding duplicate Deezer track IDs."""
        for track in candidates:
            if not track.get('preview'):
                continue

            track_id = track.get('id')
            if track_id is None:
                continue

            if track_id in seen_ids:
                continue

            seen_ids.add(track_id)
            destination.append(track)

    def search_track(self, query: str, limit: int = 25) -> Dict:
        """
        Search for tracks by query.

        Args:
            query: Search query string
            limit: Maximum number of results

        Returns:
            Dict containing search results
        """
        url = f"{self.BASE_URL}/search"
        params = {'q': query, 'limit': limit}

        try:
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            return response.json()
        except requests.RequestException as e:
            print(f"Error searching tracks: {e}")
            return {'data': []}

    def get_track(self, track_id: int) -> Optional[Dict]:
        """
        Get details of a specific track by ID.

        Args:
            track_id: Deezer track ID

        Returns:
            Dict containing track details or None if error
        """
        url = f"{self.BASE_URL}/track/{track_id}"

        try:
            response = requests.get(url, timeout=10)
            response.raise_for_status()
            return response.json()
        except requests.RequestException as e:
            print(f"Error fetching track {track_id}: {e}")
            return None

    def get_chart_tracks(self, limit: int = 50) -> List[Dict]:
        """
        Get chart (popular) tracks.

        Args:
            limit: Maximum number of tracks

        Returns:
            List of track dictionaries
        """
        url = f"{self.BASE_URL}/chart/0/tracks"
        params = {'limit': limit}

        try:
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            return data.get('data', [])
        except requests.RequestException as e:
            print(f"Error fetching chart tracks: {e}")
            return []

    def get_top_artists(self, limit: int = 200) -> List[Dict]:
        """
        Get top artists from Deezer charts.

        Args:
            limit: Maximum number of artists

        Returns:
            List of artist dictionaries
        """
        url = f"{self.BASE_URL}/chart/0/artists"
        params = {'limit': limit}

        try:
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            return data.get('data', [])
        except requests.RequestException as e:
            print(f"Error fetching top artists: {e}")
            return []

    def get_artist_top_tracks(self, artist_id: int, limit: int = 3) -> List[Dict]:
        """
        Get top tracks for a specific artist.

        Args:
            artist_id: Deezer artist ID
            limit: Maximum number of tracks

        Returns:
            List of track dictionaries
        """
        url = f"{self.BASE_URL}/artist/{artist_id}/top"
        params = {'limit': limit}

        try:
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            return data.get('data', [])
        except requests.RequestException as e:
            print(f"Error fetching top tracks for artist {artist_id}: {e}")
            return []

    def get_random_tracks_from_genre(self, genre_id: int, limit: int = 25) -> List[Dict]:
        """
        Get random tracks from a specific genre.

        Args:
            genre_id: Deezer genre ID
            limit: Maximum number of tracks

        Returns:
            List of track dictionaries
        """
        url = f"{self.BASE_URL}/genre/{genre_id}/artists"

        try:
            # Get artists from this genre
            response = requests.get(url, params={'limit': 20}, timeout=10)
            response.raise_for_status()
            artists_data = response.json()
            artists = artists_data.get('data', [])

            if not artists:
                return []

            # Pick a random artist
            random_artist = random.choice(artists)
            artist_id = random_artist['id']

            # Get top tracks from this artist
            tracks_url = f"{self.BASE_URL}/artist/{artist_id}/top"
            tracks_response = requests.get(tracks_url, params={'limit': limit}, timeout=10)
            tracks_response.raise_for_status()
            tracks_data = tracks_response.json()

            return tracks_data.get('data', [])

        except requests.RequestException as e:
            print(f"Error fetching tracks from genre {genre_id}: {e}")
            return []

    def get_genre_artists(self, genre_id: int, limit: int = 100) -> List[Dict]:
        """
        Get artists for a specific genre.

        Args:
            genre_id: Deezer genre ID
            limit: Maximum number of artists

        Returns:
            List of artist dictionaries
        """
        url = f"{self.BASE_URL}/genre/{genre_id}/artists"
        params = {'limit': limit}

        try:
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            return data.get('data', [])
        except requests.RequestException as e:
            print(f"Error fetching genre artists {genre_id}: {e}")
            return []

    def get_random_tracks(self, count: int = 10) -> List[Dict]:
        """
        Get a mix of random tracks from different genres.

        Args:
            count: Number of random tracks to fetch

        Returns:
            List of track dictionaries with preview URLs
        """
        if count <= 0:
            return []

        all_tracks: List[Dict] = []
        seen_ids: set[int] = set()

        # Pull from randomly ordered genres for variety.
        genres_to_try = self.GENRE_IDS.copy()
        random.shuffle(genres_to_try)

        for genre_id in genres_to_try:
            if len(all_tracks) >= count:
                break

            remaining = count - len(all_tracks)
            tracks = self.get_random_tracks_from_genre(
                genre_id,
                limit=min(25, max(10, remaining)),
            )
            self._collect_unique_preview_tracks(all_tracks, tracks, seen_ids)

        # Fill from chart tracks if genre sampling is short.
        if len(all_tracks) < count:
            chart_tracks = self.get_chart_tracks(limit=max(50, min(count * 2, 300)))
            self._collect_unique_preview_tracks(all_tracks, chart_tracks, seen_ids)

        # Final fill from top artists to support larger requests.
        if len(all_tracks) < count:
            artists = self.get_top_artists(limit=max(100, min(count * 2, 500)))
            random.shuffle(artists)

            for artist in artists:
                if len(all_tracks) >= count:
                    break

                artist_id = artist.get('id')
                if not artist_id:
                    continue

                remaining = count - len(all_tracks)
                artist_tracks = self.get_artist_top_tracks(
                    artist_id,
                    limit=min(5, max(3, remaining)),
                )
                self._collect_unique_preview_tracks(all_tracks, artist_tracks, seen_ids)

        random.shuffle(all_tracks)
        return all_tracks[:count]

    def extract_track_info(self, track_data: Dict) -> Dict:
        """
        Extract relevant track information from Deezer API response.

        Args:
            track_data: Raw track data from Deezer API

        Returns:
            Dict with title, artist, preview_url, and cover_url
        """
        # Get cover URL from album - prefer larger sizes
        album_data = track_data.get('album', {})
        cover_url = (
            album_data.get('cover_xl') or
            album_data.get('cover_big') or
            album_data.get('cover_medium') or
            album_data.get('cover_small') or
            album_data.get('cover', '')
        )

        return {
            'title': track_data.get('title', ''),
            'artist': track_data.get('artist', {}).get('name', ''),
            'preview_url': track_data.get('preview', ''),
            'cover_url': cover_url,
            'deezer_id': track_data.get('id'),
            'duration': track_data.get('duration', 0),
            'album': album_data.get('title', ''),
        }
