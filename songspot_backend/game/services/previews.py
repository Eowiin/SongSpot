"""
Preview URLs: fetched just in time, never stored.

Deezer signs every preview URL with a fifteen-minute expiry:

    https://cdnt-preview.dzcdn.net/api/1/1/.../<hash>.mp3
      ?hdnea=exp=1788690859~acl=...~hmac=...

Measured on 2026-09-06, `exp` is +15.0 minutes on every endpoint that returns
one — /track, /artist/{id}/top, /album/{id}/tracks, /chart, /search. So a
`preview_url` written to `tracks` is dead audio a quarter of an hour later.
That is not a seeding bug to fix; it is a property of the API, and it means the
catalogue can hold everything *about* a song except the one field needed to
play it.

Two facts decide the design:

* **There is no batch-by-ids endpoint.** `/tracks?ids=1,2,3` answers with error
  600. Resolving previews one track at a time costs one request each, and at
  sixty thousand rounds a day that is the whole quota.
* **Container endpoints return a hundred signed previews per call**, and the
  token carries `user_id=0, application_id=42` — it is bound neither to a
  player nor to the requesting IP. Production already relies on this: the
  server fetches the URL and phones all over the world stream it.

So one call serves every player on the same container for the length of the
cache window. That is what decouples request volume from user count: with
fifteen categories refreshed six times an hour, category play costs about two
thousand calls a day whether there are three thousand players or thirty
thousand.

## The window

Entries are cached for ten minutes against a fifteen-minute token, so the
oldest URL ever handed out still has five minutes of life. That has to cover
the gap between `/next-song/` answering and the phone actually starting
playback — the client prefetches a round ahead, so the URL is used within
seconds, but a player who backgrounds the app mid-round should still find
working audio when they come back.

Never widen this past twelve minutes without shortening what the client is
allowed to hold. And never hand a client a whole session's worth of URLs at
once: by the fifteenth round of a twenty-round session the first ones are gone.
One URL per round is the rule.

## Failure

`resolve` returns None rather than raising. A round with no audio is the
caller's problem to handle — usually by trying the next candidate track, and
failing that by telling the client the service is unavailable rather than
serving a round it cannot play. There is deliberately no stored fallback: a
preview URL kept in the database is expired every time it is read, so falling
back to one would only replace an honest error with silent, broken audio.
"""

import logging
from typing import Iterable, Optional

from django.conf import settings

from .cache_utils import cache_get, cache_set
from .deezer_http import DeezerHttp, DeezerUnavailable

logger = logging.getLogger(__name__)

# How long a container's previews are reused. Five minutes of headroom against
# the fifteen-minute token; see the module docstring before changing it.
POOL_TTL = 600

# A single track's preview, cached the same way. Shorter, because there is no
# sharing to amortise it — it exists only for tracks no container covers.
SINGLE_TTL = 600

# Deezer caps these endpoints at 100 items per call, verified against the live
# API. Asking for more is silently truncated, so ask for exactly the cap.
PAGE = 100

# Containers, in the order `resolve` tries them. The first is the one that
# amortises best: every player on a category shares its pool.
KIND_PATHS = {
    'playlist': '/playlist/{id}/tracks',
    'chart': '/chart/{id}/tracks',
    'artist': '/artist/{id}/top',
}


def _pool_key(kind: str, ident: int) -> str:
    return f'preview:pool:{kind}:{ident}'


def _http() -> DeezerHttp:
    # A web request is waiting, so this keeps the short MAX_WAIT default: if
    # the quota is spent, giving up quickly and letting the caller try another
    # track beats holding a worker.
    return DeezerHttp()


def _fetch_container(kind: str, ident: int) -> dict[int, str]:
    """One live call, returned as {deezer_track_id: signed_preview_url}."""
    path = KIND_PATHS[kind].format(id=ident)
    # ttl=0 and allow_stale=False force a live call every time. The sharing
    # that keeps this affordable is the ten-minute pool cache below, not
    # DeezerHttp's own — its TTLs are tuned for metadata, which stays valid for
    # days, and reusing them here would serve expired tokens for a week.
    payload = _http().get(path, {'limit': PAGE}, ttl=0, allow_stale=False)
    rows = payload.get('data') or [] if isinstance(payload, dict) else []
    return {
        row['id']: row['preview']
        for row in rows
        if isinstance(row, dict) and row.get('id') and row.get('preview')
    }


def container_previews(kind: str, ident: int) -> dict[int, str]:
    """
    Fresh previews for one container, shared across every caller for POOL_TTL.

    Returns an empty mapping when Deezer cannot be reached — the caller then
    falls back rather than failing the round.
    """
    if kind not in KIND_PATHS or not ident:
        return {}

    key = _pool_key(kind, ident)
    cached = cache_get(key)
    if cached is not None:
        return cached

    try:
        pool = _fetch_container(kind, ident)
    except DeezerUnavailable as exc:
        logger.warning('preview pool %s/%s unavailable: %s', kind, ident, exc)
        # Deliberately not cached: a miss must be retried on the next round,
        # not held for ten minutes. Deezer refusals are usually transient.
        return {}

    cache_set(key, pool, timeout=POOL_TTL)
    return pool


def single_preview(deezer_track_id: int) -> Optional[str]:
    """One track's preview, for the tracks no container happens to cover."""
    if not deezer_track_id:
        return None

    key = f'preview:track:{deezer_track_id}'
    cached = cache_get(key)
    if cached is not None:
        return cached or None

    try:
        payload = _http().get(f'/track/{deezer_track_id}', ttl=0, allow_stale=False)
    except DeezerUnavailable as exc:
        logger.warning('preview for track %s unavailable: %s', deezer_track_id, exc)
        return None

    url = payload.get('preview') if isinstance(payload, dict) else None
    if url:
        cache_set(key, url, timeout=SINGLE_TTL)
    return url or None


def playlist_containers(playlist) -> list[tuple[str, int]]:
    """
    The Deezer containers a category refills from, cheapest-sharing first.

    Editorial playlists come before the genre chart only because a category
    that has both tends to have been given playlists precisely because its
    chart was wrong for it (see the SOURCES comment in refresh_catalog).
    """
    containers: list[tuple[str, int]] = [
        ('playlist', pid) for pid in (playlist.deezer_playlist_ids or [])
    ]
    if playlist.deezer_genre_id is not None:
        containers.append(('chart', playlist.deezer_genre_id))
    return containers


def resolve(track, containers: Iterable[tuple[str, int]] = ()) -> Optional[str]:
    """
    A playable URL for `track`, or None.

    Tries the given containers in order, then the track's own artist, then a
    single-track call. The ordering is a cost ordering: a container hit is free
    once any player has warmed it, an artist pool is shared by everyone playing
    that artist, and a single-track call is shared by nobody.
    """
    if not track.deezer_id:
        return None

    # See settings.PREVIEWS_FAKE_URL. A test that reaches the network is a test
    # that fails on a train, and every round needs audio to be worth serving.
    if getattr(settings, 'PREVIEWS_FAKE_URL', False):
        return f'https://preview.test/{track.deezer_id}.mp3'

    for kind, ident in containers:
        url = container_previews(kind, ident).get(track.deezer_id)
        if url:
            return url

    if track.deezer_artist_id:
        url = container_previews('artist', track.deezer_artist_id).get(track.deezer_id)
        if url:
            return url

    return single_preview(track.deezer_id)


