"""
Shared helpers for artist-seeding management commands.
"""
import time
from typing import Optional

from game.services import DeezerService
from game.services.catalog import upsert_track
from game.services.matching import is_variant_title  # re-exported for callers

__all__ = ['is_variant_title', 'save_track', 'fetch_and_save_artist', 'resolve_artist_id']


def save_track(track_info: dict) -> str:
    """
    Persist a single track dict returned by DeezerService.

    Delegates to the catalogue's write-through upsert so a seeded track is
    stored exactly like one imported at play time — same dedup key, same
    normalised answer columns, same refreshable fields.

    Returns one of: 'added', 'updated', 'skipped'.
    """
    if is_variant_title(track_info.get('title', '')):
        return 'skipped'

    before = track_info.get('deezer_id')
    existed = False
    if before:
        from game.models import Track
        existed = Track.objects.filter(deezer_id=before).exists()

    track = upsert_track(track_info)
    if track is None:
        return 'skipped'
    return 'updated' if existed else 'added'


def fetch_and_save_artist(
    deezer: DeezerService,
    artist_id: int,
    artist_name: str,
    tracks: int,
    stdout,
    delay: float = 0.1,
) -> dict:
    """
    Fetch top `tracks` songs for an artist and save them.

    Returns {'added': int, 'updated': int, 'skipped': int}.
    """
    counts = {'added': 0, 'updated': 0, 'skipped': 0}

    # Fetch artist picture once from /artist/{id} (track responses omit it)
    artist_data = deezer.get_artist(artist_id) or {}
    artist_picture_url = (
        artist_data.get('picture_xl') or
        artist_data.get('picture_big') or
        artist_data.get('picture_medium') or
        artist_data.get('picture_small') or
        artist_data.get('picture') or
        None
    )
    if delay:
        time.sleep(delay)

    top_tracks = deezer.get_artist_top_tracks(artist_id, limit=tracks)
    if not top_tracks:
        stdout.write(f'  No tracks found for {artist_name}')
        return counts

    for track_data in top_tracks:
        track_info = deezer.enrich_track_info(track_data)
        if artist_picture_url and not track_info.get('artist_picture_url'):
            track_info['artist_picture_url'] = artist_picture_url
        result = save_track(track_info)
        counts[result] += 1
        if result == 'added':
            stdout.write(f'  + {track_info["title"]}')
        if delay:
            time.sleep(delay)

    return counts


def resolve_artist_id(deezer: DeezerService, name: str) -> Optional[int]:
    """Search Deezer for an artist by name and return their ID, or None."""
    artist = deezer.search_artist(name)
    return artist['id'] if artist else None
