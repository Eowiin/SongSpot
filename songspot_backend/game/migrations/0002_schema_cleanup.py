"""
Schema cleanup: drop old tables/columns, create new tables.
Pairs with 0001_initial which was faked (old tracks/packs tables already existed).
Database-agnostic via Django's introspection API.
"""
from django.db import migrations


OLD_TABLES = [
    'daily_game_sessions',
    'daily_songs',
    'guess_attempts',
    'pack_bundle_attempts',
    'pack_bundle_messages',
    'pack_bundle_sessions',
    'pack_bundle_stem_jobs',
    'pack_daily_tracks',
    'room_daily_mode_contributions',
    'room_daily_mode_states',
    'room_messages',
    'room_packs',
    'room_users',
    'rooms',
    'user_packs',
]

OLD_TRACK_COLUMNS = ('vocals_url', 'drums_url', 'bass_url', 'other_url')
OLD_PACK_COLUMNS = ('price_coins', 'is_free', 'auto_unlock')
OLD_PACK_TRACK_COLUMNS = ('vocals_url', 'drums_url', 'bass_url', 'other_url')


def forward(apps, schema_editor):
    conn = schema_editor.connection
    introspection = conn.introspection

    with conn.cursor() as cursor:
        existing_tables = {t.name for t in introspection.get_table_list(cursor)}

        # Drop old orphaned tables
        is_pg = conn.vendor == 'postgresql'
        cascade = 'CASCADE' if is_pg else ''
        for table in OLD_TABLES:
            if table in existing_tables:
                schema_editor.execute(f'DROP TABLE IF EXISTS "{table}" {cascade}'.strip())

        # Remove old columns from tracks
        if 'tracks' in existing_tables:
            existing_cols = {col.name for col in introspection.get_table_description(cursor, 'tracks')}
            for col in OLD_TRACK_COLUMNS:
                if col in existing_cols:
                    schema_editor.execute(f'ALTER TABLE "tracks" DROP COLUMN "{col}"')

        # Remove old columns from song_packs
        if 'song_packs' in existing_tables:
            existing_cols = {col.name for col in introspection.get_table_description(cursor, 'song_packs')}
            for col in OLD_PACK_COLUMNS:
                if col in existing_cols:
                    schema_editor.execute(f'ALTER TABLE "song_packs" DROP COLUMN "{col}"')

        # Remove old columns from pack_tracks
        if 'pack_tracks' in existing_tables:
            existing_cols = {col.name for col in introspection.get_table_description(cursor, 'pack_tracks')}
            for col in OLD_PACK_TRACK_COLUMNS:
                if col in existing_cols:
                    schema_editor.execute(f'ALTER TABLE "pack_tracks" DROP COLUMN "{col}"')

    # Create new tables using Django's schema editor (DB-agnostic)
    with conn.cursor() as cursor:
        existing_tables = {t.name for t in introspection.get_table_list(cursor)}

    GameScore = apps.get_model('game', 'GameScore')
    UserBest = apps.get_model('game', 'UserBest')

    if 'game_scores' not in existing_tables:
        schema_editor.create_model(GameScore)

    if 'user_bests' not in existing_tables:
        schema_editor.create_model(UserBest)


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0001_initial'),
    ]

    operations = [
        migrations.RunPython(forward, migrations.RunPython.noop),
    ]
