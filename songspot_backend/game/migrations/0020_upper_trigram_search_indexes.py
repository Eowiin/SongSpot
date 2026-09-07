"""
Finish what 0014 started: index the expression the query actually uses.

0014 put trigram GIN indexes on all four columns `catalog._query_filter`
touches, and its own docstring states the rule that makes them work — every
branch of the OR has to be indexable, because PostgreSQL can only build a
bitmap OR when none of them forces a scan. It indexed the columns. The query
does not read the columns.

Django compiles `icontains` on PostgreSQL to `UPPER(col) LIKE UPPER(%s)`, and
an index on `title` cannot answer a predicate on `upper(title)`. So two of the
four branches stayed unindexable, and by 0014's own rule that is the same as
having indexed nothing: the planner fell back to a sequential scan over the
whole table, every keystroke.

Measured on production, 355k rows, searching "heart":

    all four branches      Parallel Seq Scan   1019.912 ms   11648 buffers
    without the UPPER two  BitmapOr on trgm      77.709 ms    1129 buffers

These two indexes are on `upper(col::text)`, matching the generated predicate
exactly, so all four branches become indexable and the plan collapses to a
bitmap OR.

This was urgent rather than merely nice: the catalogue is written through on
every search, so `tracks` grows by roughly 90 000 rows an hour under load, and
a sequential scan gets linearly worse while a bitmap OR does not.

CONCURRENTLY, because the table takes writes continuously and a plain CREATE
INDEX would hold them off for the length of the build. That forces
`atomic = False`: CONCURRENTLY cannot run inside a transaction. A concurrent
build that fails leaves an INVALID index behind rather than rolling back —
check with `\\d tracks` and DROP it before re-running if that happens.

Followed by ANALYZE, which is not optional: an expression index has no
statistics until ANALYZE runs after its creation, and the planner will keep
picking the sequential scan until it does.

IF NOT EXISTS, so the migration is a no-op where the index has already been
created by hand. Applying a concurrent index to a loaded server ahead of the
deploy that carries the migration is a reasonable thing to do, and this lets
the two orders converge.
"""

from django.db import migrations

UPPER_TRIGRAM_INDEXES = [
    ('tracks_upper_title_trgm', 'tracks', 'title'),
    ('tracks_upper_artist_trgm', 'tracks', 'artist'),
]


def create_upper_trigram_indexes(apps, schema_editor):
    if schema_editor.connection.vendor != 'postgresql':
        return
    with schema_editor.connection.cursor() as cursor:
        for name, table, column in UPPER_TRIGRAM_INDEXES:
            cursor.execute(
                f'CREATE INDEX CONCURRENTLY IF NOT EXISTS {name} '
                f'ON {table} USING gin (upper({column}::text) gin_trgm_ops)'
            )
        # An expression index carries no statistics until ANALYZE runs *after*
        # it exists, and without them the planner keeps choosing the sequential
        # scan this migration was written to eliminate. Observed on production:
        # both indexes valid, both ignored, until an explicit ANALYZE — at
        # which point the plan collapsed to a bitmap OR and the query went from
        # 252 ms to 26 ms. Autoanalyze would get there eventually; leaving the
        # gap open means an unknown stretch of production still scanning.
        for table in dict.fromkeys(t for _, t, _ in UPPER_TRIGRAM_INDEXES):
            cursor.execute(f'ANALYZE {table}')


def drop_upper_trigram_indexes(apps, schema_editor):
    if schema_editor.connection.vendor != 'postgresql':
        return
    with schema_editor.connection.cursor() as cursor:
        for name, _, _ in UPPER_TRIGRAM_INDEXES:
            cursor.execute(f'DROP INDEX CONCURRENTLY IF EXISTS {name}')


class Migration(migrations.Migration):

    # CREATE INDEX CONCURRENTLY cannot run inside a transaction block.
    atomic = False

    dependencies = [
        ('game', '0019_clear_borrowed_artist_pictures'),
    ]

    operations = [
        migrations.RunPython(
            create_upper_trigram_indexes,
            drop_upper_trigram_indexes,
        ),
    ]
