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
        all_tracks = []

        # Fetch from multiple genres
        genres_to_try = random.sample(self.GENRE_IDS, min(3, len(self.GENRE_IDS)))

        for genre_id in genres_to_try:
            tracks = self.get_random_tracks_from_genre(genre_id, limit=10)
            # Filter tracks that have preview URLs
            valid_tracks = [t for t in tracks if t.get('preview')]
            all_tracks.extend(valid_tracks)

        # If not enough tracks, fetch from charts
        if len(all_tracks) < count:
            chart_tracks = self.get_chart_tracks(limit=50)
            valid_chart_tracks = [t for t in chart_tracks if t.get('preview')]
            all_tracks.extend(valid_chart_tracks)

        # Shuffle and return requested count
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
