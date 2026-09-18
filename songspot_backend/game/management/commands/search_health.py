import json
from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db.models import Count
from django.db import connection
from django.utils import timezone
from game.models import Track, Artist, SearchOutbox, SearchEnrichment
from game.services.search_index import Index


class Command(BaseCommand):
    help = 'Read-only search completeness, backlog and provider state report (no Deezer calls).'

    def handle(self, *args, **options):
        oldest = SearchOutbox.objects.order_by('created_at').first()
        report = {
            'backend': settings.SEARCH_BACKEND,
            'external_index_enabled': settings.SEARCH_INDEX_ENABLED,
            'outbox': SearchOutbox.objects.count(),
            'oldest_event_seconds': (timezone.now()-oldest.created_at).total_seconds() if oldest else 0,
            'enrichment_states': list(SearchEnrichment.objects.values('state').annotate(count=Count('id'))),
            'missing_search_fields': Track.objects.filter(search_title='', search_artist='').exclude(norm_title='', norm_artist='').count(),
        }
        expected_indexes = [f'tracks_search_{field}_{suffix}' for field in ('title','artist') for suffix in ('trgm','prefix')]
        expected_indexes.append('artists_blocked_search')
        expected_indexes.append('tracks_search_words')
        expected_indexes.append('tracks_search_rank')
        expected_indexes.append('artists_upper_name_trgm')
        expected_indexes.extend(f'tracks_search_{field}_short_rank' for field in ('title', 'artist'))
        with connection.cursor() as cursor:
            cursor.execute('SELECT indexrelid::regclass::text, indisvalid FROM pg_index WHERE indexrelid::regclass::text = ANY(%s)', [expected_indexes])
            report['sql_indexes'] = dict(cursor.fetchall())
        if settings.SEARCH_INDEX_ENABLED:
            index = Index()
            blocked = Artist.objects.filter(is_blocked=True).values('pk')
            for kind, expected in [('tracks', Track.objects.exclude(deezer_artist_id__in=blocked).count()),
                                   ('artists', Artist.objects.filter(is_blocked=False).count())]:
                stats = index.request('GET', '/indexes/songspot_'+kind+'/stats')
                report[kind] = {'expected_documents': expected, 'indexed_documents': stats['numberOfDocuments'], 'indexing': stats['isIndexing']}
        self.stdout.write(json.dumps(report))
        if len(report['sql_indexes']) != len(expected_indexes) or not all(report['sql_indexes'].values()) or report['missing_search_fields'] or (settings.SEARCH_INDEX_ENABLED and (report['outbox'] or any(
            report[k]['expected_documents'] != report[k]['indexed_documents'] or report[k]['indexing'] for k in ('tracks','artists')
        ))):
            raise CommandError('Search projection not yet complete')
