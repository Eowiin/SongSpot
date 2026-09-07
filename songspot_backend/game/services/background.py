"""
Fire-and-forget work, bounded on purpose.

The catalogue grows by watching what players search for, but a player must
never wait for that growth: the search box has to answer from Postgres and let
the Deezer round-trip happen after the response has been sent.

This is a thread pool *inside the existing Django process* — there is no daemon
to start, nothing to install, and nothing extra running on a development
machine. Celery would mean a broker, a separate worker process, a systemd unit
and a deployment change, which is a lot of moving parts for work whose entire
failure mode is "the catalogue learns this song a bit later". The interface
here is deliberately the one Celery would offer, so swapping it later touches
this file and nothing else.

Three rules make an in-process pool safe on a web server:

* **A full queue drops work.** Enrichment is opportunistic; a request that
  cannot be queued is a missed opportunity, never an error. Blocking to wait
  for a slot would put the latency straight back into the request it was
  supposed to keep out of.
* **Every task closes its database connections.** A pool thread is not a
  request, so nothing else will; without this, each thread holds a Postgres
  connection open for the life of the process.
* **A task's exception dies with the task.** Nothing awaits these futures, so
  an unhandled error would vanish silently — it is logged here instead.
"""

import logging
import threading
from concurrent.futures import ThreadPoolExecutor
from typing import Callable

from django.conf import settings
from django.db import connections

logger = logging.getLogger(__name__)

# Small on purpose. These threads compete with request handling for CPU and,
# more importantly, share the Deezer rate limit with the players' own rounds.
MAX_WORKERS = 4

# Once this many tasks are outstanding, new ones are dropped. Sized to absorb a
# burst of distinct searches without letting a queue build up that would still
# be draining minutes later, long after the results stopped being interesting.
MAX_PENDING = 32

_executor = ThreadPoolExecutor(max_workers=MAX_WORKERS, thread_name_prefix='songspot-bg')
_lock = threading.Lock()
_pending = 0


def pending() -> int:
    """Tasks queued or running. Exposed for tests and diagnostics."""
    with _lock:
        return _pending


def _run(fn: Callable, args: tuple, kwargs: dict) -> None:
    global _pending
    try:
        fn(*args, **kwargs)
    except Exception:
        logger.exception('background task %s failed', getattr(fn, '__name__', fn))
    finally:
        # A pool thread outlives any request, so Django's own teardown never
        # runs for it. Left alone, each of these threads would pin one Postgres
        # connection forever.
        connections.close_all()
        with _lock:
            _pending -= 1


def submit(fn: Callable, *args, **kwargs) -> bool:
    """
    Queue `fn` to run after the response. False when it will not run.

    Disabled unless `settings.BACKGROUND_TASKS_ENABLED` — off in development
    and under test. Locally that means no thread is ever started and no Deezer
    call happens behind your back; the search box just answers from whatever
    the local database holds. Under test it also keeps assertions from racing
    work that may or may not have finished; tests call the task functions
    directly instead.
    """
    global _pending
    if not getattr(settings, 'BACKGROUND_TASKS_ENABLED', False):
        return False

    with _lock:
        if _pending >= MAX_PENDING:
            logger.info('background queue full — dropping %s', getattr(fn, '__name__', fn))
            return False
        _pending += 1

    try:
        _executor.submit(_run, fn, args, kwargs)
    except RuntimeError:
        # Interpreter shutting down.
        with _lock:
            _pending -= 1
        return False
    return True
