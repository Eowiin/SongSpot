"""Update only the already-created synthetic fixture after an unapplied migration edit."""
import importlib
from postgres_scale import connection, settings
assert settings.DATABASES['default']['NAME']=='search_test'
assert settings.DATABASES['default']['HOST']=='db'
module=importlib.import_module('game.migrations.0025_search_triggers')
with connection.cursor() as cursor:
    cursor.execute(module.SQL.split('CREATE OR REPLACE FUNCTION songspot_search_track_fields')[0])
    cursor.execute('''UPDATE tracks SET search_title=songspot_search_text(title),
        search_artist=songspot_search_text(artist)
        WHERE search_title <> normalize(search_title, NFKD)
           OR search_artist <> normalize(search_artist, NFKD)''')
    print('Local fixture normalization updated:',cursor.rowcount)
