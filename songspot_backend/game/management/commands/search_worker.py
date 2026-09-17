import time
from django.conf import settings
from django.core.management.base import BaseCommand
from game.models import SearchOutbox
from game.services.search_index import Index, consumer_lock, drain
from game.services.search_enrichment import run_one


class Command(BaseCommand):
    help = 'Durable index/enrichment worker. Supervise with systemd.'

    def add_arguments(self, parser):
        parser.add_argument('--once', action='store_true')

    def handle(self, *args, **options):
        with consumer_lock():
            while True:
                if settings.SEARCH_INDEX_ENABLED:
                    indexed = drain(Index())
                else:
                    # No external projection in PostgreSQL mode. A later
                    # activation of Meilisearch requires a full rebuild.
                    ids = list(SearchOutbox.objects.order_by('id').values_list('id', flat=True)[:1000])
                    indexed = SearchOutbox.objects.filter(pk__in=ids).delete()[0] if ids else 0
                enriched = run_one() if settings.SEARCH_ENRICHMENT_ENABLED else False
                if options['once']:
                    break
                if not indexed and not enriched:
                    time.sleep(.5)
