"""One async I/O loop per process; cancellation never waits for a DNS thread.

asyncio.run() shuts down its default executor and can wait for getaddrinfo even
when the request deadline already expired. A persistent loop avoids that wait.
Only transport work lives here; enrichment jobs remain durable in PostgreSQL.
"""
import asyncio
import os
import threading

_lock = threading.Lock()
_loop = None
_pid = None


def run_bounded(coroutine, timeout):
    global _loop, _pid
    with _lock:
        if _loop is None or _pid != os.getpid():
            _loop = asyncio.new_event_loop()
            _pid = os.getpid()
            threading.Thread(target=_loop.run_forever, name='deezer-network', daemon=True).start()
        loop = _loop
    future = asyncio.run_coroutine_threadsafe(coroutine, loop)
    try:
        return future.result(timeout=max(0, timeout))
    except TimeoutError:
        future.cancel()
        raise
