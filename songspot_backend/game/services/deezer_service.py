import random
from typing import Optional, Dict, List

from .deezer_http import (
    DeezerHttp,
    DeezerUnavailable,
    TTL_ARTIST,
    TTL_ARTIST_TOP,
    TTL_CHART,
    TTL_SEARCH,
    TTL_TRACK,
)


class DeezerService:
    """
    Service to interact with Deezer API.

    Every call goes through DeezerHttp, which caches responses and paces them
    against Deezer's ~50 requests / 5 s per-IP quota. The methods here keep
    their original contract of returning an empty list or None on failure:
    callers reach this class from request paths that must degrade to the local
    catalogue rather than raise. Use `self.http` directly when the caller does
    want to distinguish "no results" from "Deezer is down".
    """
    BASE_URL = "https://api.deezer.com"

    def __init__(self, http: Optional[DeezerHttp] = None):
        self.http = http or DeezerHttp()

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

    # Map Deezer genre ID → human-readable name used when storing tracks
    GENRE_NAMES = {
        132: 'Pop',
        116: 'Rap/Hip-Hop',
        152: 'Rock',
        113: 'Dance',
        165: 'R&B',
        129: 'Jazz',
        85:  'Alternative',
        106: 'Electronic',
        464: 'Indie Pop',
    }

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

    def search_artist(self, name: str) -> Optional[Dict]:
        """
        Search for an artist by name and return the best match.

        Returns the first result dict (id, name, picture_*) or None.
        """
        try:
            data = self.http.get(
                '/search/artist', {'q': name, 'limit': 5}, ttl=TTL_SEARCH,
            )
        except DeezerUnavailable:
            return None
        results = data.get('data', [])
        return results[0] if results else None

    def search_track(self, query: str, limit: int = 25) -> Dict:
        """
        Search for tracks by query.

        Args:
            query: Search query string
            limit: Maximum number of results

        Returns:
            Dict containing search results
        """
        try:
            return self.http.get(
                '/search', {'q': query, 'limit': limit}, ttl=TTL_SEARCH,
            )
        except DeezerUnavailable:
            return {'data': []}

    def get_track(self, track_id: int) -> Optional[Dict]:
        """
        Get details of a specific track by ID.

        Args:
            track_id: Deezer track ID

        Returns:
            Dict containing track details or None if error
        """
        try:
            return self.http.get(f'/track/{track_id}', ttl=TTL_TRACK)
        except DeezerUnavailable:
            return None

    def get_album(self, album_id: int) -> Optional[Dict]:
        """
        Get details of a specific album by ID.

        Args:
            album_id: Deezer album ID

        Returns:
            Dict containing album details or None if error
        """
        try:
            return self.http.get(f'/album/{album_id}', ttl=TTL_TRACK)
        except DeezerUnavailable:
            return None

    def get_chart_tracks(self, limit: int = 50) -> List[Dict]:
        """
        Get chart (popular) tracks.

        Args:
            limit: Maximum number of tracks

        Returns:
            List of track dictionaries
        """
        try:
            data = self.http.get('/chart/0/tracks', {'limit': limit}, ttl=TTL_CHART)
        except DeezerUnavailable:
            return []
        return data.get('data', [])

    def get_top_artists(self, limit: int = 200) -> List[Dict]:
        """
        Get top artists from Deezer charts.

        Args:
            limit: Maximum number of artists

        Returns:
            List of artist dictionaries
        """
        try:
            data = self.http.get('/chart/0/artists', {'limit': limit}, ttl=TTL_CHART)
        except DeezerUnavailable:
            return []
        return data.get('data', [])

    def get_artist(self, artist_id: int) -> Optional[Dict]:
        """Fetch a single artist by ID (includes picture_* fields)."""
        try:
            return self.http.get(f'/artist/{artist_id}', ttl=TTL_ARTIST)
        except DeezerUnavailable:
            return None

    def get_artist_top_tracks(self, artist_id: int, limit: int = 3) -> List[Dict]:
        """
        Get top tracks for a specific artist.

        Args:
            artist_id: Deezer artist ID
            limit: Maximum number of tracks

        Returns:
            List of track dictionaries
        """
        try:
            data = self.http.get(
                f'/artist/{artist_id}/top', {'limit': limit}, ttl=TTL_ARTIST_TOP,
            )
        except DeezerUnavailable:
            return []
        return data.get('data', [])

    def get_related_artists(self, artist_id: int, limit: int = 20) -> List[Dict]:
        """
        Artists Deezer considers adjacent to this one. Twenty per call.

        This is the crawler's edge list. Walking it from a few hundred chart
        artists reaches the long tail far more cheaply than searching for names
        we would have to know in advance — and knowing them in advance is
        exactly the problem, since a missing artist is invisible until someone
        leaves a review about it.
        """
        try:
            data = self.http.get(
                f'/artist/{artist_id}/related', {'limit': limit}, ttl=TTL_ARTIST,
            )
        except DeezerUnavailable:
            return []
        return data.get('data', [])

    def search_artists(self, query: str, limit: int = 25) -> List[Dict]:
        """
        Search artists by name, best match *last* to be sorted by the caller.

        Deezer's own ordering is not usable for picking an artist to play:
        `search/artist?q=weeknd` returns "Weeknd" (2k fans) ahead of
        "The Weeknd" (14.6M). Callers re-rank on `nb_fan`.
        """
        try:
            data = self.http.get(
                '/search/artist', {'q': query, 'limit': limit}, ttl=TTL_SEARCH,
            )
        except DeezerUnavailable:
            return []
        return data.get('data', [])

    def get_artist_albums(self, artist_id: int, limit: int = 100, index: int = 0) -> List[Dict]:
        """
        List an artist's albums, for going deeper than the 50-track top.

        A long session on one artist exhausts `/artist/{id}/top`; the albums are
        where the rest of the discography lives.
        """
        try:
            data = self.http.get(
                f'/artist/{artist_id}/albums',
                {'limit': limit, 'index': index},
                ttl=TTL_ARTIST_TOP,
            )
        except DeezerUnavailable:
            return []
        return data.get('data', [])

    def get_album_tracks(self, album_id: int, limit: int = 100) -> List[Dict]:
        """
        Track list of one album.

        Album track payloads omit the album object, so callers that need cover
        art should carry it over from the album they came from.
        """
        try:
            data = self.http.get(
                f'/album/{album_id}/tracks', {'limit': limit}, ttl=TTL_TRACK,
            )
        except DeezerUnavailable:
            return []
        return data.get('data', [])

    def get_random_tracks_from_genre(self, genre_id: int, limit: int = 25) -> List[Dict]:
        """
        Get random tracks from a specific genre.

        Args:
            genre_id: Deezer genre ID
            limit: Maximum number of tracks

        Returns:
            List of track dictionaries
        """
        artists = self.get_genre_artists(genre_id, limit=20)
        if not artists:
            return []

        random_artist = random.choice(artists)
        tracks = self.get_artist_top_tracks(random_artist['id'], limit=limit)

        # Annotate each track with the genre name so callers can store it
        genre_name = self.GENRE_NAMES.get(genre_id)
        if genre_name:
            for track in tracks:
                track['_genre_name'] = genre_name
        return tracks

    def list_genres(self) -> List[Dict]:
        """
        Return all Deezer genres with their IDs. Useful for verifying genre IDs
        before seeding packs (run with --list-genres flag in seed command).
        """
        try:
            return self.http.get('/genre', ttl=TTL_CHART).get('data', [])
        except DeezerUnavailable:
            return []

    def get_genre_chart_tracks(self, genre_id: int, limit: int = 100, index: int = 0) -> List[Dict]:
        """
        Get chart tracks for a specific genre from Deezer's editorial charts.
        More geographically stable than fetching via genre artists.

        Args:
            genre_id: Deezer genre ID (use list_genres() to verify IDs)
            limit: Maximum number of tracks per page
            index: Offset for pagination (0, 100, 200, …)

        Returns:
            List of track dicts with 'rank' field included
        """
        try:
            data = self.http.get(
                f'/chart/{genre_id}/tracks',
                {'limit': limit, 'index': index},
                ttl=TTL_CHART,
            )
        except DeezerUnavailable:
            return []
        return data.get('data', [])

    def get_playlist_tracks(self, playlist_id: int, limit: int = 100, index: int = 0) -> List[Dict]:
        """
        Get tracks from a Deezer editorial playlist.
        Used for categories without a dedicated Deezer genre ID (Rap FR, Bollywood).

        Args:
            playlist_id: Deezer playlist ID
            limit: Maximum number of tracks

        Returns:
            List of track dicts
        """
        try:
            data = self.http.get(
                f'/playlist/{playlist_id}/tracks',
                {'limit': limit, 'index': index},
                ttl=TTL_CHART,
            )
        except DeezerUnavailable:
            return []
        return data.get('data', [])

    def get_genre_artists(self, genre_id: int, limit: int = 100) -> List[Dict]:
        """
        Get artists for a specific genre.

        Args:
            genre_id: Deezer genre ID
            limit: Maximum number of artists

        Returns:
            List of artist dictionaries
        """
        try:
            data = self.http.get(
                f'/genre/{genre_id}/artists', {'limit': limit}, ttl=TTL_CHART,
            )
        except DeezerUnavailable:
            return []
        return data.get('data', [])

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

    @staticmethod
    def _parse_release_year(raw_date) -> Optional[int]:
        if not raw_date:
            return None

        try:
            return int(str(raw_date)[:4])
        except (ValueError, TypeError):
            return None

    @classmethod
    def _extract_primary_genre_name(cls, payload: Optional[Dict]) -> Optional[str]:
        if not isinstance(payload, dict):
            return None

        genre_name = payload.get('_genre_name')
        if genre_name:
            return genre_name

        genres = payload.get('genres', {})
        genre_items = genres.get('data', []) if isinstance(genres, dict) else []
        for genre in genre_items:
            name = genre.get('name')
            if name:
                return name

        genre_id = payload.get('genre_id')
        if genre_id:
            return cls.GENRE_NAMES.get(genre_id)

        return None

    def extract_track_info(self, track_data: Dict, fallback_genre: Optional[str] = None) -> Dict:
        """
        Extract relevant track information from Deezer API response.

        Args:
            track_data: Raw track data from Deezer API
            fallback_genre: Fallback genre to store when Deezer does not provide one

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

        # Extract release year from track or album release_date (format: "YYYY-MM-DD" or "YYYY")
        release_year = self._parse_release_year(
            track_data.get('release_date') or album_data.get('release_date', '')
        )
        genre = (
            self._extract_primary_genre_name(track_data) or
            self._extract_primary_genre_name(album_data) or
            fallback_genre
        )

        artist_data = track_data.get('artist', {})
        artist_picture_url = (
            artist_data.get('picture_xl') or
            artist_data.get('picture_big') or
            artist_data.get('picture_medium') or
            artist_data.get('picture_small') or
            artist_data.get('picture') or
            None
        )

        # Truncated to the column widths in game.models.Track. Deezer serves the
        # occasional title carrying its whole remix credit, and an overlong one
        # does not fail alone: it raises DataError inside a bulk_create and takes
        # the other 199 rows of the batch down with it.
        return {
            'contributors': [
                {'id': c.get('id'), 'name': str(c['name'])[:255]}
                for c in (track_data.get('contributors') or [])[:20]
                if isinstance(c, dict) and c.get('name')
            ],
            'title': track_data.get('title', '')[:255],
            'artist': artist_data.get('name', '')[:255],
            # The artist *entity*, not the credited name. Two releases of one
            # song can spell the credit differently; the ID does not move.
            'deezer_artist_id': artist_data.get('id'),
            'preview_url': track_data.get('preview', ''),
            'cover_url': cover_url,
            'deezer_id': track_data.get('id'),
            'duration': track_data.get('duration', 0),
            'album': album_data.get('title', ''),
            'release_year': release_year,
            'genre': genre[:100] if genre else genre,
            'rank': track_data.get('rank', 0),
            'artist_picture_url': artist_picture_url,
        }

    def enrich_track_info(self, track_data: Dict, fallback_genre: Optional[str] = None) -> Dict:
        """
        Enrich partial track payloads with missing metadata from Deezer track/album endpoints.

        Search and chart endpoints often omit `release_date` and genre information. This
        helper fetches the full track and album only when needed.
        """
        info = self.extract_track_info(track_data, fallback_genre=fallback_genre)
        resolved_track_data = track_data

        if info.get('deezer_id') and (
            not info.get('release_year') or
            not info.get('genre') or
            not info.get('cover_url')
        ):
            full_track_data = self.get_track(info['deezer_id'])
            if full_track_data:
                resolved_track_data = full_track_data
                full_info = self.extract_track_info(full_track_data, fallback_genre=fallback_genre)
                for key in ('preview_url', 'cover_url', 'release_year', 'genre'):
                    if full_info.get(key):
                        info[key] = full_info[key]

        album_id = (resolved_track_data.get('album') or {}).get('id')
        if album_id and (
            not info.get('release_year') or
            not info.get('genre') or
            not info.get('cover_url')
        ):
            album_data = self.get_album(album_id)
            if album_data:
                if not info.get('release_year'):
                    info['release_year'] = self._parse_release_year(album_data.get('release_date'))
                if not info.get('genre'):
                    info['genre'] = self._extract_primary_genre_name(album_data)
                if not info.get('cover_url'):
                    info['cover_url'] = (
                        album_data.get('cover_xl') or
                        album_data.get('cover_big') or
                        album_data.get('cover_medium') or
                        album_data.get('cover_small') or
                        album_data.get('cover') or
                        info.get('cover_url')
                    )

        if not info.get('genre') and fallback_genre:
            info['genre'] = fallback_genre

        return info
