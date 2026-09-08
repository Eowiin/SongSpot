"""
Guards the wrapper every consumer DB helper has to use.

A consumer's worker thread outlives the socket, so nothing else will hand its
Postgres connection back. `database_sync_to_async` closes it; asgiref's bare
`sync_to_async` does not. Swapping one for the other is a one-word edit that
looks harmless in review and takes production down slowly: every player in a
duel pins a connection for the whole match until the server runs out of slots
and *every* endpoint starts refusing to connect.
"""

import inspect

from asgiref.sync import SyncToAsync
from channels.db import DatabaseSyncToAsync
from django.test import SimpleTestCase

from game import consumers


class ConsumerDatabaseWrapperTests(SimpleTestCase):
    CONSUMERS = (consumers.MatchmakingConsumer, consumers.DuelConsumer)

    @staticmethod
    def _raw_members(klass):
        """
        Every attribute of `klass`, inherited ones included, unwrapped.

        Two things have to be true at once here and only this pairing gives
        both. `getattr` would run the descriptor protocol and hand back a bound
        partial, losing the wrapper type the test is looking for — hence
        `getattr_static`. And reading `vars(klass)` instead would dodge the
        descriptor but stop at the class's own namespace, so the day a helper
        moves to a shared mixin the guard would quietly stop covering it —
        hence `dir`, which walks the MRO.
        """
        for name in dir(klass):
            if name.startswith('__'):
                continue
            try:
                yield name, inspect.getattr_static(klass, name)
            except AttributeError:
                continue

    def test_every_sync_helper_closes_its_connection(self):
        offenders = [
            f'{klass.__name__}.{name}'
            for klass in self.CONSUMERS
            for name, member in self._raw_members(klass)
            if isinstance(member, SyncToAsync)
            and not isinstance(member, DatabaseSyncToAsync)
        ]

        self.assertEqual(
            offenders, [],
            'these wrap sync work without closing the connection — use '
            'channels.db.database_sync_to_async, not asgiref sync_to_async',
        )

    def test_the_guard_can_actually_see_the_helpers(self):
        # Without this, a refactor that renamed or removed every helper would
        # leave the test above passing over an empty set and guarding nothing.
        wrapped = {
            name
            for klass in self.CONSUMERS
            for name, member in self._raw_members(klass)
            if isinstance(member, DatabaseSyncToAsync)
        }
        self.assertIn('_join_queue', wrapped)
        self.assertIn('_get_or_create_elo', wrapped)
        self.assertGreaterEqual(len(wrapped), 15)
