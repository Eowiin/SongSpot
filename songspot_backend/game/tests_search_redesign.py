from datetime import timedelta
from unittest.mock import patch
from concurrent.futures import ThreadPoolExecutor
from django.test import TestCase, TransactionTestCase, override_settings
from django.db import connection, close_old_connections
from django.utils import timezone
from game.models import Artist, Track, SearchEnrichment, SearchOutbox, DeezerBudget
from game.services import catalog, search_enrichment
from game.services.deezer_http import DeezerUnavailable
from game.services.deezer_budget import reserve


class SearchRegressionTests(TestCase):
    def setUp(self):
        self.artist = Artist.objects.create(deezer_id=1,name='Simple Minds')

    def track(self,title,artist='Simple Minds', **kwargs):
        return Track.objects.create(title=title,artist=artist,deezer_artist_id=1,**kwargs)

    def test_full_parenthetical_and_short_words(self):
        song=self.track("Don't You (Forget About Me)")
        self.assertIn(song, catalog._candidates(catalog._query_filter(song.title),song.title))

    def test_no_preview_searchable_not_playable(self):
        song=catalog.upsert_track(dict(title='A Song',artist='Simple Minds',deezer_id=44))
        self.assertIsNotNone(song)
        self.assertFalse(song.has_preview)
        self.assertFalse(catalog.playable(Track.objects.filter(pk=song.pk),directed=True).exists())

    def test_no_artist_cap_or_name_collision(self):
        songs=[Track.objects.create(title='INTRO',artist='Same name',deezer_artist_id=i,rank=i) for i in range(10,20)]
        self.assertEqual(len(catalog._dedupe(songs,40,'intro')),10)

    def test_artist_exact_precedes_popular_substrings(self):
        song=self.track('Rare song','NeS',rank=1)
        others=[self.track('The Motion Picture '+str(i),'Genesis',rank=999999) for i in range(220)]
        self.assertEqual(catalog._dedupe([song]+others,40,'nes')[0],song)

    def test_blocked_artist_never_returned(self):
        song=self.track('Secret Song')
        self.artist.is_blocked=True;self.artist.save()
        self.assertEqual(catalog._dedupe([song],40,'Secret Song'),[])

    def test_transactional_outbox_on_bulk_update_and_delete(self):
        if connection.vendor!='postgresql':self.skipTest('PostgreSQL triggers required')
        song=self.track('First')
        SearchOutbox.objects.all().delete()
        Track.objects.filter(pk=song.pk).update(title='Second (Full Title)')
        song.refresh_from_db()
        self.assertEqual(song.search_title,'second full title')
        self.assertTrue(SearchOutbox.objects.filter(kind='tracks',entity_id=str(song.pk)).exists())
        song.delete()
        self.assertEqual(SearchOutbox.objects.filter(kind='tracks').count(),2)

    def test_job_failure_retry_and_abandoned_lease(self):
        search_enrichment.schedule('tracks','new band')
        with patch('game.services.search_enrichment.DeezerHttp.get',side_effect=DeezerUnavailable()):
            self.assertTrue(search_enrichment.run_one())
        row=SearchEnrichment.objects.get()
        self.assertEqual(row.state,'failed')
        self.assertLess(row.next_attempt_at-timezone.now(),timedelta(minutes=6))
        row.state='running';row.lease_until=timezone.now()-timedelta(seconds=1);row.save()
        self.assertIsNotNone(search_enrichment.claim())

    def test_empty_success_and_dedup_distinct(self):
        for _ in range(4):search_enrichment.schedule('artists','unknown')
        self.assertEqual(SearchEnrichment.objects.count(),1)
        with patch('game.services.search_enrichment.DeezerHttp.get',return_value={'data':[]}):
            search_enrichment.run_one()
        row=SearchEnrichment.objects.get()
        self.assertEqual(row.state,'empty')
        self.assertLess(row.next_attempt_at-timezone.now(),timedelta(hours=7))

    @override_settings(SEARCH_BACKEND='legacy', SEARCH_ENRICHMENT_ENABLED=False)
    def test_v2_and_legacy_contract(self):
        from rest_framework.test import APIRequestFactory
        from game.views import SearchTracksView
        self.track('Example')
        factory=APIRequestFactory()
        with patch.object(catalog,'_enrich_later'):
            old=SearchTracksView.as_view()(factory.get('/',{'q':'example'}))
        new=SearchTracksView.as_view()(factory.get('/',{'q':'example','v':'2'}))
        self.assertIsInstance(old.data,list)
        self.assertIsInstance(new.data['results'],list)
        self.assertIn('enrichment',new.data)


class BudgetConcurrencyTests(TransactionTestCase):
    def test_global_window_and_reservations(self):
        if connection.vendor!='postgresql':self.skipTest('PostgreSQL required')
        DeezerBudget.objects.create(pk=1)
        def take(_):
            close_old_connections()
            try:return reserve('preview')
            finally:close_old_connections()
        with ThreadPoolExecutor(max_workers=8) as pool:
            allowed=list(pool.map(take,range(80)))
        self.assertEqual(sum(allowed),40)
        self.assertFalse(reserve('background'))
        row=DeezerBudget.objects.get(pk=1)
        self.assertEqual(len(row.calls),40)
        row.calls=[t-5.1 for t in row.calls];row.save()
        self.assertTrue(reserve('preview'))


class TransportDeadlineTests(TestCase):
    def test_quota_preserves_callers_transaction_timeouts(self):
        if connection.vendor != 'postgresql':
            self.skipTest('PostgreSQL required')
        with connection.cursor() as cursor:
            cursor.execute("SET LOCAL lock_timeout = '2s'")
            cursor.execute("SET LOCAL statement_timeout = '3s'")
        for occupied, expected in [(0, True), (40, False)]:
            DeezerBudget.objects.update_or_create(
                pk=1, defaults={'calls': [timezone.now().timestamp()] * occupied},
            )
            self.assertEqual(reserve('preview'), expected)
            with connection.cursor() as cursor:
                cursor.execute("SELECT current_setting('lock_timeout'), current_setting('statement_timeout')")
                self.assertEqual(cursor.fetchone(), ('2s', '3s'))

    @override_settings(TESTING=False)
    def test_total_deadline_cancels_slow_network(self):
        import asyncio
        import time
        from unittest.mock import AsyncMock
        from game.services.deezer_http import DeezerHttp
        async def slow(*args, **kwargs):
            await asyncio.sleep(1)
        client = AsyncMock()
        client.__aenter__.return_value = client
        client.get.side_effect = slow
        start = time.monotonic()
        with patch('game.services.deezer_http.httpx.AsyncClient', return_value=client), patch('game.services.deezer_http._rate_limit_slot', return_value=True):
            with self.assertRaises(DeezerUnavailable):
                DeezerHttp(max_wait=.05)._fetch('/search', None)
        self.assertLess(time.monotonic()-start, .3)

    @override_settings(TESTING=False)
    def test_http_429_and_body_code_4_are_not_empty(self):
        import httpx
        from unittest.mock import Mock
        from game.services.deezer_http import DeezerHttp
        for response in [httpx.Response(429, request=httpx.Request('GET','https://api.deezer.com/search')),
                         httpx.Response(200, json={'error':{'code':4}}, request=httpx.Request('GET','https://api.deezer.com/search'))]:
            session=Mock();session.get.return_value=response
            with patch('game.services.deezer_http._rate_limit_slot',return_value=True):
                with self.assertRaises(DeezerUnavailable):
                    DeezerHttp(session=session,max_wait=.1)._fetch('/search',None)

    def test_coordination_loss_fails_closed(self):
        from django.db import DatabaseError
        with patch('game.services.deezer_budget.DeezerBudget.objects.get_or_create',side_effect=DatabaseError('offline')):
            self.assertFalse(reserve('preview'))


class RollingWindowTests(TestCase):
    def test_fixed_window_boundary_cannot_double_budget(self):
        from game.services.deezer_budget import admit
        calls = []
        for _ in range(40):
            calls = admit(calls, 4.999, 'preview')
        self.assertIsNone(admit(calls, 5.001, 'preview'))
        self.assertIsNone(admit(calls, 9.998, 'preview'))
        self.assertEqual(admit(calls, 10.0, 'preview'), [10.0])

    def test_lower_priorities_preserve_preview_headroom(self):
        from game.services.deezer_budget import admit
        calls = [1.0]*24
        self.assertIsNone(admit(calls, 2.0, 'background'))
        self.assertIsNotNone(admit(calls, 2.0, 'search'))
        calls = [1.0]*34
        self.assertIsNone(admit(calls, 2.0, 'search'))
        self.assertIsNotNone(admit(calls, 2.0, 'preview'))


class EnrichmentVisibilityTests(TestCase):
    @override_settings(SEARCH_BACKEND='postgres', SEARCH_ENRICHMENT_ENABLED=False)
    def test_typo_result_visible_before_index_catches_up(self):
        from game.services.search import search
        song = Track.objects.create(title='Shape of You', artist='Ed Sheeran', deezer_id=123)
        SearchEnrichment.objects.create(kind='tracks', norm_query='ed sheran',
            enriched_at=timezone.now(), state='succeeded', track_ids=[str(song.pk)])
        self.assertIn(song, search('tracks', 'ed sheran', enqueue=False)['rows'])

    @override_settings(SEARCH_BACKEND='postgres', SEARCH_ENRICHMENT_ENABLED=False)
    def test_unrelated_remembered_results_are_not_suggestions(self):
        from game.services.search import search
        song = Track.objects.create(title='Unrelated', artist='Different Act')
        SearchEnrichment.objects.create(kind='tracks', norm_query='ed sheran',
            enriched_at=timezone.now(), state='succeeded', track_ids=[str(song.pk)])
        self.assertEqual(search('tracks', 'ed sheran', enqueue=False)['rows'], [])


class ContributorTests(TestCase):
    def test_credits_are_search_aliases_without_changing_answer_identity(self):
        from game.services.search_index import documents
        rows=catalog.upsert_tracks([{'id':321, 'title':'A Collaboration',
            'artist':{'id':123, 'name':'Primary Artist'},
            'contributors':[{'id':124, 'name':'Guest Artist'}]}])
        row=Track.objects.get(pk=rows[0].pk)
        self.assertEqual(row.norm_artist,'primary artist')
        self.assertIn('guest artist',documents('tracks',[row])[0]['aliases'])
        self.assertFalse(row.has_preview)
        Artist.objects.filter(pk=123).update(name='Renamed Primary')
        self.assertIn('renamed primary',documents('tracks',[row])[0]['aliases'])


class RetryPolicyTests(TestCase):
    def test_new_queries_precede_background_retries(self):
        old = SearchEnrichment.objects.create(kind='tracks', norm_query='old', state='failed',
            enriched_at=timezone.now(), next_attempt_at=timezone.now()-timedelta(hours=1))
        search_enrichment.schedule('tracks','new')
        self.assertNotEqual(search_enrichment.claim().pk, old.pk)

    def test_failed_queries_stop_retrying_until_requested_again(self):
        row = SearchEnrichment.objects.create(kind='tracks', norm_query='unknown', state='failed',
            enriched_at=timezone.now(), next_attempt_at=timezone.now(), attempts=7)
        with patch('game.services.search_enrichment.DeezerHttp.get',side_effect=DeezerUnavailable()):
            search_enrichment.run_one()
        row.refresh_from_db()
        self.assertEqual(row.state,'failed')
        self.assertIsNone(row.next_attempt_at)
        self.assertIsNone(search_enrichment.claim())
        search_enrichment.schedule('tracks','unknown')
        self.assertIsNotNone(search_enrichment.claim())


class BlockedGameplayTests(TestCase):
    def test_hard_block_applies_to_directed_rounds_despite_warm_quality_cache(self):
        artist = Artist.objects.create(pk=9876, name='An Artist')
        track = Track.objects.create(title='A Title', artist=artist.name, deezer_artist_id=artist.pk,
                                    deezer_id=54321, has_preview=True)
        catalog.clear_junk_artist_cache()
        catalog.junk_artist_ids()
        Artist.objects.filter(pk=artist.pk).update(is_blocked=True)
        self.assertFalse(catalog.playable(Track.objects.filter(pk=track.pk), directed=True).exists())
        Artist.objects.filter(pk=artist.pk).update(is_blocked=False)
        self.assertTrue(catalog.playable(Track.objects.filter(pk=track.pk), directed=True).exists())


@override_settings(SEARCH_BACKEND='postgres', SEARCH_INDEX_ENABLED=False)
class PostgresWorkerTests(TestCase):
    @override_settings(SEARCH_ENRICHMENT_ENABLED=True)
    def test_worker_without_external_index_discards_only_one_bounded_batch(self):
        if connection.vendor != 'postgresql':
            self.skipTest('PostgreSQL advisory lock required')
        from django.core.management import call_command
        SearchOutbox.objects.all().delete()
        SearchOutbox.objects.bulk_create([
            SearchOutbox(kind='tracks', entity_id=str(i)) for i in range(1001)
        ])
        with patch('game.management.commands.search_worker.Index') as index, patch(
            'game.management.commands.search_worker.run_one', return_value=True,
        ) as enrichment:
            call_command('search_worker', once=True)
        index.assert_not_called()
        enrichment.assert_called_once_with()
        self.assertEqual(SearchOutbox.objects.count(), 1)

    @override_settings(SEARCH_ENRICHMENT_ENABLED=False)
    def test_disabled_enrichment_never_contacts_provider(self):
        if connection.vendor != 'postgresql':
            self.skipTest('PostgreSQL advisory lock required')
        from django.core.management import call_command
        with patch('game.management.commands.search_worker.Index') as index, patch(
            'game.management.commands.search_worker.run_one',
        ) as enrichment:
            call_command('search_worker', once=True)
        index.assert_not_called()
        enrichment.assert_not_called()


class ShortPrefixTests(TestCase):
    def test_two_letters_match_later_words_in_title_and_artist(self):
        song = Track.objects.create(title='Love You', artist='Nono La Grinta', rank=100)
        first_word = Track.objects.create(title='Yodel', artist='Someone', rank=1)
        artist = Track.objects.create(title='Heart of Gold', artist='Neil Young')
        unrelated = Track.objects.create(title='Beyond', artist='Someone', rank=999999)
        rows = catalog._dedupe(catalog._candidates(catalog._query_filter('yo'), 'yo'), 40, 'yo')
        self.assertIn(song, rows)
        self.assertIn(artist, rows)
        self.assertNotIn(unrelated, rows)
        self.assertLess(rows.index(song), rows.index(first_word))

    def test_later_word_prefix_still_respects_artist_blocks(self):
        Artist.objects.create(deezer_id=89, name='Nono La Grinta', is_blocked=True)
        hidden = Track.objects.create(title='Love You', artist='Nono La Grinta', deezer_artist_id=89)
        self.assertNotIn(hidden, catalog._candidates(catalog._query_filter('yo'), 'yo'))

    def test_two_letter_query_keeps_exact_title_and_both_prefix_fields(self):
        exact = Track.objects.create(title='Li', artist='Rare act', rank=1)
        title = Track.objects.create(title='Light', artist='Other act', rank=100)
        artist = Track.objects.create(title='Song', artist='Little band', rank=200)
        unrelated = Track.objects.create(title='Climb', artist='Unrelated', rank=999999)
        rows = catalog._dedupe(catalog._candidates(catalog._query_filter('li'), 'li'), 40, 'li')
        self.assertEqual(rows[0], exact)
        self.assertIn(title, rows)
        self.assertIn(artist, rows)
        self.assertNotIn(unrelated, rows)

    def test_two_letter_lanes_apply_artist_blocks(self):
        blocked = Artist.objects.create(deezer_id=88, name='Little band', is_blocked=True)
        hidden = Track.objects.create(title='Light', artist=blocked.name, deezer_artist_id=88)
        self.assertNotIn(hidden, catalog._candidates(catalog._query_filter('li'), 'li'))


class CompleteTitleArtistTests(TestCase):
    def test_repeated_title_artist_survives_popular_substring_candidates(self):
        artist = Artist.objects.create(deezer_id=18, name='NeS')
        wanted = Track.objects.create(title='Nés', artist=artist.name, deezer_artist_id=18, rank=1)
        Track.objects.bulk_create([
            Track(title=f'Late goodness {i}', artist='Other act', rank=999999,
                  search_title=f'late goodness {i}', search_artist='other act')
            for i in range(220)
        ])
        rows = catalog._dedupe(catalog._candidates(catalog._query_filter('Nés NeS'), 'Nés NeS'), 40, 'Nés NeS')
        self.assertEqual(rows[0], wanted)

    def test_full_hangul_title_and_artist_remain_searchable(self):
        song = Track.objects.create(title='봄날', artist='방탄소년단')
        query = '봄날 방탄소년단'
        self.assertIn(song, catalog._candidates(catalog._query_filter(query), query))
        song.refresh_from_db()
        from game.services.matching import normalize_query
        self.assertEqual(song.search_title, normalize_query(song.title))
