"""
Cache access that cannot take the game down with it.

Opening the catalogue put a cache on the critical path: every Deezer call
checks it, the rate limiter counts through it, and every pick reads the catalog
settings from it. Django's Redis backend propagates connection errors, so
without this wrapper a Redis outage would stop being a performance problem and
become a total outage — every round, for every player.

Two protections:

* **A failure reads as a miss.** The game then runs uncached: slower, and
  closer to Deezer's quota, but serving.
* **A breaker stops the bleeding.** Each failed call costs a connect timeout,
  and paying that on every lookup is its own outage — a page that needs a dozen
  cache reads would take a dozen seconds. After a few consecutive failures the
  shared cache is skipped for a cooldown, then retried.
* **Degraded means local, not absent.** While the breaker is open, reads and
  writes go to an in-process cache instead. This matters more than it sounds:
  the Deezer rate limiter counts through here, so a cache that vanished
  entirely would leave it counting nothing and pacing nothing — it would wave
  every request straight through to an API that allows fifty per five seconds.
  The first version did exactly that, and a bulk import promptly exhausted the
  quota and failed every category after the second.

This deliberately uses its own alias rather than `default`. Django and DRF
reach for `default` themselves — DRF's throttling calls it on every game
request and raises if it errors — so `default` has to stay local and always
available. See the CACHES block in settings.
"""

import logging
import time
from typing import Any, Optional

from django.core.cache import caches

logger = logging.getLogger(__name__)

CACHE_ALIAS = 'deezer'
LOCAL_ALIAS = 'deezer_local'

# Consecutive failures before the cache is treated as down.
_BREAKER_THRESHOLD = 3
# How long to skip it for once the breaker trips.
_BREAKER_COOLDOWN = 30.0

_failures = 0
_skip_until = 0.0

# Redis client errors, plus anything else a backend may raise on a dead
# connection. Deliberately broad: the fallback is always safe, and a wrapper
# that lets an unexpected exception through defeats its own purpose.
_ERRORS = Exception


def _cache():
    """The shared cache, or the in-process one while the breaker is open."""
    return caches[CACHE_ALIAS] if _available() else caches[LOCAL_ALIAS]


def _available() -> bool:
    """False while the shared cache is being skipped."""
    return time.monotonic() >= _skip_until


def is_degraded() -> bool:
    """True when running on the in-process fallback."""
    return not _available()


def _failed(op: str, key: str, exc: BaseException) -> None:
    global _failures, _skip_until
    _failures += 1
    if _failures >= _BREAKER_THRESHOLD:
        _skip_until = time.monotonic() + _BREAKER_COOLDOWN
        _failures = 0
        logger.warning(
            'Cache unreachable (%s on %s: %s) — skipping it for %.0fs',
            op, key, exc, _BREAKER_COOLDOWN,
        )


def _succeeded() -> None:
    global _failures
    if _failures:
        _failures = 0


def cache_get(key: str, default: Any = None) -> Any:
    try:
        value = _cache().get(key, default)
    except _ERRORS as exc:
        _failed('get', key, exc)
        try:
            return caches[LOCAL_ALIAS].get(key, default)
        except _ERRORS:
            return default
    _succeeded()
    return value


def cache_set(key: str, value: Any, timeout: Optional[int] = None) -> bool:
    try:
        _cache().set(key, value, timeout=timeout)
    except _ERRORS as exc:
        _failed('set', key, exc)
        try:
            caches[LOCAL_ALIAS].set(key, value, timeout=timeout)
        except _ERRORS:
            return False
        return True
    _succeeded()
    return True


def cache_add(key: str, value: Any, timeout: Optional[int] = None) -> bool:
    """
    True when this caller created the key.

    False when someone else holds it. A failure falls through to the local
    cache rather than answering False outright: the rate limiter reads this,
    and a bare False there would look like "window already open" forever.
    """
    try:
        created = bool(_cache().add(key, value, timeout=timeout))
    except _ERRORS as exc:
        _failed('add', key, exc)
        try:
            return bool(caches[LOCAL_ALIAS].add(key, value, timeout=timeout))
        except _ERRORS:
            return False
    _succeeded()
    return created


def cache_incr(key: str, delta: int = 1) -> Optional[int]:
    """The new value, or None when the key is gone."""
    try:
        value = _cache().incr(key, delta)
    except ValueError:
        # Key expired between add and incr. Not a cache failure.
        return None
    except _ERRORS as exc:
        _failed('incr', key, exc)
        try:
            return caches[LOCAL_ALIAS].incr(key, delta)
        except ValueError:
            return None
        except _ERRORS:
            return None
    _succeeded()
    return value


def cache_delete(key: str) -> None:
    try:
        _cache().delete(key)
    except _ERRORS as exc:
        _failed('delete', key, exc)
    else:
        _succeeded()
    try:
        caches[LOCAL_ALIAS].delete(key)
    except _ERRORS:
        pass


def reset_breaker() -> None:
    """Clear the breaker. For tests, and for anything that knows Redis is back."""
    global _failures, _skip_until
    _failures = 0
    _skip_until = 0.0
