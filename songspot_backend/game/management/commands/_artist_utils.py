"""
Shared helpers for artist-seeding management commands.
"""
import re
import time
from typing import Optional

from game.models import Track
from game.services import DeezerService

UPDATABLE_FIELDS = ('cover_url', 'deezer_id', 'release_year', 'genre', 'artist_picture_url')

# Matches parenthetical/bracketed variant suffixes, e.g. "(2011 Remaster)", "[Live at Wembley]", "(Acoustic Version)"
_VARIANT_RE = re.compile(
    r'[\(\[]\s*(?:\d{4}\s+)?'
    r'(?:remaster(?:ed)?'
    r'|live(?:\s+(?:at|from|version|recording))?'
    r'|acoustic(?:\s+version)?'
    r'|demo(?:\s+version)?'
    r'|instrumental(?:\s+version)?'
    r'|karaoke'
    r'|radio\s+edit'
    r'|single\s+(?:version|edit)'
    r'|album\s+version'
    r'|anniversary\s+edition'
    r'|mono(?:\s+version)?'
    r')',
    re.IGNORECASE,
)

# Matches dash-separated suffixes, e.g. "Song Title - Live" or "Song Title - Remastered"
_VARIANT_SUFFIX_RE = re.compile(
    r'\s+[-–]\s+(?:live|remaster(?:ed)?|acoustic|demo|instrumental|karaoke)(?:\s+.*)?$',
    re.IGNORECASE,
)


def is_variant_title(title: str) -> bool:
    """Return True if the title looks like a remaster, live, acoustic, demo or similar variant."""
    return bool(_VARIANT_RE.search(title) or _VARIANT_SUFFIX_RE.search(title))


def save_track(track_info: dict) -> str:
    """
    Persist a single track dict returned by DeezerService.

    Returns one of: 'added', 'updated', 'skipped'.
    """
    if not track_info.get('preview_url'):
        return 'skipped'

    if is_variant_title(track_info.get('title', '')):
        return 'skipped'

    existing = Track.objects.filter(
        title=track_info['title'],
        artist=track_info['artist'],
    ).first()

    if existing:
        update_fields = []
        for field in UPDATABLE_FIELDS:
            new_value = track_info.get(field)
            if not new_value:
                continue
            if getattr(existing, field) in (None, ''):
                setattr(existing, field, new_value)
                update_fields.append(field)
        if update_fields:
            existing.save(update_fields=update_fields)
            return 'updated'
        return 'skipped'

    Track.objects.create(
        title=track_info['title'],
        artist=track_info['artist'],
        preview_url=track_info['preview_url'],
        cover_url=track_info.get('cover_url'),
        deezer_id=track_info.get('deezer_id'),
        release_year=track_info.get('release_year'),
        genre=track_info.get('genre'),
        artist_picture_url=track_info.get('artist_picture_url'),
    )
    return 'added'


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
