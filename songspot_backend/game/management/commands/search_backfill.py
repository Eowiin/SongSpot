from django.core.management.base import BaseCommand
from django.db import connection
from game.models import Track
from game.services.matching import normalize_query


class Command(BaseCommand):
    help = 'Resumable bounded backfill of full search fields; run before activating search.'

    def handle(self, *args, **options):
        count = 0
        after = None
        while True:
            pending = Track.objects.filter(search_title='', search_artist='')
            if after is not None:
                pending = pending.filter(pk__gt=after)
            rows = list(pending.order_by('pk')[:500])
            if not rows:
                break
            after = rows[-1].pk
            if connection.vendor == 'postgresql':
                with connection.cursor() as cursor:
                    cursor.execute("UPDATE tracks SET search_title=songspot_search_text(title), search_artist=songspot_search_text(artist) WHERE id = ANY(%s)", [[r.pk for r in rows]])
                count += len(rows)
                if count % 50000 == 0:
                    self.stdout.write(f'Backfilled {count} tracks', ending='\n')
                    self.stdout.flush()
                continue
            for row in rows:
                row.search_title = normalize_query(row.title)
                row.search_artist = normalize_query(row.artist)
            Track.objects.bulk_update(rows, ['search_title', 'search_artist'], batch_size=500)
            count += len(rows)
        if connection.vendor == 'postgresql':
            # Outside transactions: avoid blocking ordinary writes during build.
            with connection.cursor() as cursor:
                definitions = []
                for field in ('search_title', 'search_artist'):
                    definitions.extend([
                        (f'tracks_{field}_trgm', f'ON tracks USING gin ({field} gin_trgm_ops)'),
                        (f'tracks_{field}_prefix', f'ON tracks ({field} text_pattern_ops)'),
                        (f'tracks_{field}_short_rank', f'ON tracks (left({field}, 2), rank DESC, id)'),
                    ])
                definitions.extend([
                    ('tracks_search_rank', 'ON tracks (rank DESC, id)'),
                    ('tracks_search_words', "ON tracks USING gin (to_tsvector('simple', search_title || ' ' || search_artist))"),
                    ('artists_blocked_search', 'ON artists (deezer_id) WHERE is_blocked'),
                    ('artists_upper_name_trgm', 'ON artists USING gin (upper(name::text) gin_trgm_ops)'),
                ])
                for name, definition in definitions:
                    cursor.execute('SELECT indisvalid FROM pg_index WHERE indexrelid = to_regclass(%s)', [name])
                    existing = cursor.fetchone()
                    if existing and not existing[0]:
                        # A cancelled concurrent build leaves an invalid index;
                        # IF NOT EXISTS alone would silently keep it unusable.
                        self.stdout.write(f'Rebuilding interrupted index {name}')
                        cursor.execute(f'DROP INDEX CONCURRENTLY {name}')
                    cursor.execute(f'CREATE INDEX CONCURRENTLY IF NOT EXISTS {name} {definition}')
                cursor.execute('ANALYZE tracks')
                cursor.execute('ANALYZE artists')
        self.stdout.write(str(count))
