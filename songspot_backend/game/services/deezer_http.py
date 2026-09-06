"""
The cached, rate-limited transport under DeezerService.

Deezer's public API allows roughly **50 requests per 5 seconds per IP**, and
every player's traffic leaves through this one host. Autocomplete alone fires a
search per keystroke, so without a cache in front the app would exhaust the
quota for everybody as soon as a handful of people type at the same time. This
module is therefore not an optimisation — it is the thing that makes an open
catalogue possible on a shared IP.

Three behaviours matter:

* **One entry, two ages.** A response is stored once under a long expiry with
  its fetch time. Inside its TTL it is a fresh hit; past it, it stays as a
  fallback. So a quota exhaustion or a Deezer outage degrades to slightly stale
  data instead of a failed round.
* **Requests wait, briefly, rather than fail.** A shared counter paces live
  calls. A caller that cannot get through within `MAX_WAIT` raises rather than
  holding a worker thread.
* **Callers are expected to have a local fallback.** `DeezerUnavailable` means
  "serve from the database", never "show the player an error".
"""

import hashlib
import json
import logging
import time
from typing import Any, Optional

import requests
from django.conf import settings

from .cache_utils import cache_add, cache_get, cache_incr, cache_set

logger = logging.getLogger(__name__)

BASE_URL = "https://api.deezer.com"

# How long a response stays *fresh*, per kind of data. Charts move daily, an
# artist's top tracks barely move at all, and a track's own metadata never
# meaningfully changes (its preview URL does, but that has its own refresh path
# in Track.get_fresh_preview_url).
TTL_SEARCH = 60 * 60 * 24            # 1 day
TTL_ARTIST_TOP = 60 * 60 * 24 * 7    # 7 days
TTL_CHART = 60 * 60 * 24             # 1 day
TTL_TRACK = 60 * 60 * 24 * 30        # 30 days
TTL_ARTIST = 60 * 60 * 24 * 7        # 7 days

# How long a stale copy is kept as a fallback once its TTL has passed.
STALE_TTL = 60 * 60 * 24 * 60        # 60 days

# Deezer's documented ceiling is 50 requests / 5 s per IP. We pace to 40 to
# leave room for the small race in the shared counter and for anything else on
# this host talking to Deezer (the refresh cron, a management command).
RATE_LIMIT = 40
RATE_WINDOW = 5

# Longest a *web request* will pace itself before giving up on a live call. A
# player waiting on a round cannot be held much longer than this, and the caller
# always has the database to fall back on.
MAX_WAIT = 2.0

# Background jobs have the opposite trade-off: nobody is waiting, and giving up
# means an empty category. A bulk import should queue behind the limiter for as
# long as it takes rather than burn through the quota and fail.
BULK_MAX_WAIT = 120.0

REQUEST_TIMEOUT = 10

# Backoff between retries of a refused call, doubling up to the ceiling.
RETRY_BACKOFF = 1.0
RETRY_BACKOFF_MAX = 15.0

# Deezer error codes worth waiting out rather than giving up on. 4 is the quota
# breach; the rest are its transient siblings. A 404 or a bad ID is not here on
# purpose — retrying those just burns the budget.
_TRANSIENT_CODES = {4, 700, 800}
_TRANSIENT_WORDS = ('quota', 'limit', 'busy', 'temporar', 'unavailable')


class DeezerUnavailable(Exception):
    """
    Deezer could not be reached, or the quota is spent and nothing is cached.

    Callers must treat this as "fall back to the local catalogue", not as an
    error to surface: the database always holds every track ever served.
    """


def _cache_key(path: str, params: Optional[dict]) -> str:
    raw = path + '?' + json.dumps(params or {}, sort_keys=True)
    return 'deezer:' + hashlib.sha1(raw.encode()).hexdigest()


def _rate_limit_slot() -> bool:
    """
    Claim one slot in the current window. False when the window is full.

    A fixed window rather than a rolling one: it is one cache round-trip
    instead of a sorted-set read, and the cost of the coarser edge is already
    covered by pacing to 40 instead of 50.
    """
    key = f'deezer:rl:{int(time.time() // RATE_WINDOW)}'
    # `add` returns False when the key already exists, which is the signal that
    # someone else opened this window and we should increment instead.
    if cache_add(key, 1, timeout=RATE_WINDOW + 1):
        return True
    count = cache_incr(key)
    if count is None:
        # The window expired between `add` and `incr`. A genuinely new window,
        # so there is a slot. This branch must never be reachable *because the
        # cache is missing*: cache_utils falls back to an in-process cache
        # precisely so the count always lands somewhere. A limiter that fails
        # open stops being a limiter at the worst possible moment.
        return True
    return count <= RATE_LIMIT


def _is_transient(error: Any) -> bool:
    """Whether a Deezer error body describes something that may pass."""
    if not isinstance(error, dict):
        return False
    if error.get('code') in _TRANSIENT_CODES:
        return True
    message = f"{error.get('message', '')} {error.get('type', '')}".lower()
    return any(word in message for word in _TRANSIENT_WORDS)


class DeezerHttp:
    """Cached, paced access to the Deezer public API."""

    def __init__(
        self,
        session: Optional[requests.Session] = None,
        max_wait: float = MAX_WAIT,
    ):
        self._session = session or requests.Session()
        self._max_wait = max_wait

    def get(
        self,
        path: str,
        params: Optional[dict] = None,
        ttl: int = TTL_SEARCH,
        allow_stale: bool = True,
    ) -> Any:
        """
        Fetch `path`, preferring a fresh cache entry.

        Raises DeezerUnavailable when there is neither a live response nor a
        stale copy to fall back on.
        """
        key = _cache_key(path, params)
        entry = cache_get(key)
        now = time.time()

        if entry and now - entry.get('t', 0) < ttl:
            return entry['d']

        stale = entry['d'] if entry and allow_stale else None

        try:
            data = self._fetch(path, params)
        except DeezerUnavailable:
            if stale is not None:
                logger.warning('Deezer unavailable for %s — serving stale cache', path)
                return stale
            raise

        cache_set(key, {'t': now, 'd': data}, timeout=STALE_TTL)
        return data

    def _fetch(self, path: str, params: Optional[dict]) -> Any:
        """
        One live call, paced and retried within the caller's time budget.

        Our own limiter keeps us under the quota, but Deezer counts per IP and
        can refuse anyway — anything else on this host talking to it counts
        too. A refusal is transient, so it is worth waiting out rather than
        giving up: a single refused chart request used to leave a whole
        category empty for the day.

        How long that is worth doing is the caller's call, not ours. A web
        request has a player waiting and a database to fall back on, so it
        gives up in about two seconds; a nightly import has neither, and waits.
        """
        # A test that reaches the network is a test that fails on a train. The
        # suite must exercise *our* rules, so an un-mocked call here is turned
        # into the same outcome as an outage — which every caller already knows
        # how to handle by falling back to the database.
        if getattr(settings, 'TESTING', False):
            raise DeezerUnavailable(f'{path}: live calls are disabled under test')

        deadline = time.time() + self._max_wait
        url = f'{BASE_URL}{path}'
        backoff = RETRY_BACKOFF
        last: Optional[str] = None

        while True:
            while not _rate_limit_slot():
                if time.time() >= deadline:
                    raise DeezerUnavailable(f'rate limit exhausted for {path}')
                time.sleep(0.25)

            try:
                response = self._session.get(url, params=params, timeout=REQUEST_TIMEOUT)
                response.raise_for_status()
                payload = response.json()
            except (requests.RequestException, ValueError) as exc:
                last = str(exc)
            else:
                # Deezer answers 200 with an error body rather than an HTTP
                # status, so a quota breach only shows up in the payload.
                if not (isinstance(payload, dict) and 'error' in payload):
                    return payload
                last = str(payload['error'])
                if not _is_transient(payload['error']):
                    raise DeezerUnavailable(f'{path}: {last}')

            if time.time() + backoff >= deadline:
                raise DeezerUnavailable(f'{path}: {last}')
            logger.info('Deezer refused %s (%s) — retrying in %.1fs', path, last, backoff)
            time.sleep(backoff)
            backoff = min(backoff * 2, RETRY_BACKOFF_MAX)
