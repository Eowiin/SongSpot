"""PostgreSQL deployment recovery checks on Django's isolated test database."""
import io
import json
from django.core.management import call_command
from django.db import connection, DatabaseError
from django.test import TransactionTestCase, override_settings
from game.models import Track, SearchOutbox


@override_settings(SEARCH_BACKEND='postgres', SEARCH_INDEX_ENABLED=False)
class SearchDeploymentTests(TransactionTestCase):
    def test_interrupted_index_build_is_repaired_and_local_outbox_does_not_block_readiness(self):
        if connection.vendor != 'postgresql':
            self.skipTest('PostgreSQL concurrent indexes required')
        Track.objects.create(title='First', artist='Band', rank=1)
        Track.objects.create(title='Second', artist='Band', rank=1)
        with connection.cursor() as cursor:
            cursor.execute('DROP INDEX CONCURRENTLY IF EXISTS tracks_search_title_short_rank')
            with self.assertRaises(DatabaseError):
                cursor.execute('CREATE UNIQUE INDEX CONCURRENTLY tracks_search_title_short_rank ON tracks (rank)')
            cursor.execute("SELECT indisvalid FROM pg_index WHERE indexrelid='tracks_search_title_short_rank'::regclass")
            self.assertFalse(cursor.fetchone()[0])
        call_command('search_backfill', stdout=io.StringIO())
        with connection.cursor() as cursor:
            cursor.execute("SELECT indisvalid, pg_get_indexdef(indexrelid) FROM pg_index WHERE indexrelid='tracks_search_title_short_rank'::regclass")
            valid, definition = cursor.fetchone()
        self.assertTrue(valid)
        self.assertIn('"left"(search_title, 2)', definition)
        self.assertGreater(SearchOutbox.objects.count(),0)
        output=io.StringIO()
        call_command('search_health', stdout=output)
        report=json.loads(output.getvalue())
        self.assertFalse(report['external_index_enabled'])
        self.assertEqual(len(report['sql_indexes']),8)
