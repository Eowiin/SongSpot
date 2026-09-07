"""
Make the local search survive a large catalogue.

`catalog._query_filter` matches each token against four columns with
`contains` / `icontains`, which is a leading-wildcard LIKE. No B-tree index can
serve that, so every autocomplete keystroke was a sequential scan. Unnoticeable
over four thousand rows, fatal at a million — and P1 made this the *only* thing
between a player and their results, since the search no longer falls through to
Deezer.

Trigram GIN indexes are what make a leading-wildcard LIKE indexable in
PostgreSQL.

Two things worth knowing before editing this:

* **All four columns need one, not just the normalised pair.** The filter ORs
  the raw and normalised columns together, and PostgreSQL can only build a
  bitmap OR when *every* branch is indexable. Index two of the four and the
  planner falls back to a sequential scan anyway, which looks exactly like
  having done nothing.
* **The indexes are created in SQL rather than declared in `Meta.indexes`.**
  Development runs on SQLite, which has neither pg_trgm nor GIN, and a declared
  index would make every migration fail there. The cost is that
  `makemigrations` cannot see them: they exist in the database and in this
  file, and nowhere else.

The two B-tree indexes dropped here were already dead weight — a B-tree on
`title` cannot answer `title LIKE '%x%'`, which is the only way `title` is ever
queried. `is_curated` goes for a different reason: a boolean index over a
roughly even split is more expensive to consult than the scan it replaces.
"""

from django.db import migrations, models

TRIGRAM_INDEXES = [
    ('tracks_title_trgm', 'tracks', 'title'),
    ('tracks_artist_trgm', 'tracks', 'artist'),
    ('tracks_norm_title_trgm', 'tracks', 'norm_title'),
    ('tracks_norm_artist_trgm', 'tracks', 'norm_artist'),
    ('artists_name_trgm', 'artists', 'name'),
    ('artists_norm_name_trgm', 'artists', 'norm_name'),
]


def create_trigram_indexes(apps, schema_editor):
    if schema_editor.connection.vendor != 'postgresql':
        return
    with schema_editor.connection.cursor() as cursor:
        cursor.execute('CREATE EXTENSION IF NOT EXISTS pg_trgm')
        for name, table, column in TRIGRAM_INDEXES:
            cursor.execute(
                f'CREATE INDEX IF NOT EXISTS {name} '
                f'ON {table} USING gin ({column} gin_trgm_ops)'
            )


def drop_trigram_indexes(apps, schema_editor):
    if schema_editor.connection.vendor != 'postgresql':
        return
    with schema_editor.connection.cursor() as cursor:
        for name, _, _ in TRIGRAM_INDEXES:
            cursor.execute(f'DROP INDEX IF EXISTS {name}')


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0013_track_is_variant_searchmiss'),
    ]

    operations = [
        migrations.RemoveIndex(model_name='track', name='tracks_title_f94b39_idx'),
        migrations.RemoveIndex(model_name='track', name='tracks_artist_707385_idx'),
        migrations.AlterField(
            model_name='track',
            name='is_curated',
            field=models.BooleanField(default=False),
        ),
        migrations.RunPython(create_trigram_indexes, drop_trigram_indexes),
    ]
