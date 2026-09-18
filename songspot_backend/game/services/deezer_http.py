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

import asyncio
import httpx
import hashlib
import json
import logging
import time
from typing import Any, Optional

import requests
from django.conf import settings

from .cache_utils import cache_get, cache_set

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

# Historical 2015 ceiling, not reconfirmed as a current guarantee.
# All consumers share the durable rolling budget in deezer_budget.py.
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


def _rate_limit_slot(priority='search') -> bool:
    from .deezer_budget import reserve
    return reserve(priority)


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
        priority: str = 'search',
    ):
        self._session = session
        self._max_wait = max_wait
        self._priority = 'background' if max_wait == BULK_MAX_WAIT else priority

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
            logger.info('deezer_cache priority=%s outcome=fresh', self._priority)
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

    def _network_get(self, url, params, remaining):
        if self._session is not None:
            # Injectable synchronous session for deterministic transport tests.
            from urllib3.util import Timeout
            return self._session.get(url, params=params, timeout=Timeout(total=remaining))

        async def request():
            async with httpx.AsyncClient(timeout=remaining) as client:
                return await client.get(url, params=params)

        async def bounded():
            return await asyncio.wait_for(request(), timeout=remaining)

        # Cancellation bounds DNS, connection, headers and full body together.
        # Django calls this synchronous service from its sync worker threads.
        from .network_loop import run_bounded
        return run_bounded(bounded(), remaining)

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

        deadline = time.monotonic() + self._max_wait
        url = f'{BASE_URL}{path}'
        backoff = RETRY_BACKOFF
        last: Optional[str] = None

        while True:
            quota_started = time.monotonic()
            while not _rate_limit_slot(self._priority):
                if time.monotonic() >= deadline:
                    raise DeezerUnavailable(f'rate limit exhausted for {path}')
                time.sleep(min(0.05, max(0, deadline-time.monotonic())))

            remaining = deadline-time.monotonic()
            if remaining <= 0:
                raise DeezerUnavailable(f'{path}: deadline exhausted')
            logger.info('deezer_outbound priority=%s quota_wait_ms=%.3f',
                        self._priority, (time.monotonic()-quota_started)*1000)
            try:
                response = self._network_get(url, params, min(REQUEST_TIMEOUT, remaining))
                response.raise_for_status()
                payload = response.json()
            except (requests.RequestException, httpx.HTTPError, TimeoutError, ValueError) as exc:
                last = str(exc)
            else:
                # Deezer answers 200 with an error body rather than an HTTP
                # status, so a quota breach only shows up in the payload.
                if not (isinstance(payload, dict) and 'error' in payload):
                    if time.monotonic() > deadline:
                        raise DeezerUnavailable(f'{path}: deadline exhausted')
                    return payload
                last = str(payload['error'])
                if not _is_transient(payload['error']):
                    raise DeezerUnavailable(f'{path}: {last}')

            if time.monotonic() + backoff >= deadline:
                raise DeezerUnavailable(f'{path}: {last}')
            logger.info('Deezer refused %s (%s) — retrying in %.1fs', path, last, backoff)
            time.sleep(backoff)
            backoff = min(backoff * 2, RETRY_BACKOFF_MAX)
