from django.db import migrations

SQL = r"""
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE OR REPLACE FUNCTION songspot_search_text(value text) RETURNS text
LANGUAGE sql STABLE AS $$
 SELECT trim(regexp_replace(regexp_replace(lower(normalize(unaccent(replace(value, '&', ' and ')), NFKD)), '[^[:alnum:]_[:space:]]', ' ', 'g'), '[[:space:]]+', ' ', 'g'))
$$;
CREATE OR REPLACE FUNCTION songspot_search_track_fields() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 NEW.search_title := songspot_search_text(NEW.title);
 NEW.search_artist := songspot_search_text(NEW.artist);
 RETURN NEW;
END $$;
CREATE TRIGGER search_track_fields BEFORE INSERT OR UPDATE OF title, artist ON tracks
FOR EACH ROW EXECUTE FUNCTION songspot_search_track_fields();
CREATE OR REPLACE FUNCTION songspot_search_event() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE entity text;
BEGIN
 IF TG_TABLE_NAME = 'tracks' THEN
   IF TG_OP = 'DELETE' THEN entity := OLD.id::text; ELSE entity := NEW.id::text; END IF;
 ELSE
   IF TG_OP = 'DELETE' THEN entity := OLD.deezer_id::text; ELSE entity := NEW.deezer_id::text; END IF;
 END IF;
 INSERT INTO search_outbox(kind, entity_id, created_at) VALUES (TG_TABLE_NAME, entity, clock_timestamp());
 RETURN NULL;
END $$;
CREATE TRIGGER search_track_event AFTER INSERT OR DELETE OR UPDATE OF title, artist, rank, deezer_artist_id ON tracks
FOR EACH ROW EXECUTE FUNCTION songspot_search_event();
CREATE TRIGGER search_artist_event AFTER INSERT OR DELETE OR UPDATE OF name, nb_fan, is_blocked, is_junk ON artists
FOR EACH ROW EXECUTE FUNCTION songspot_search_event();
"""
REVERSE = '''
DROP TRIGGER IF EXISTS search_track_event ON tracks;
DROP TRIGGER IF EXISTS search_artist_event ON artists;
DROP TRIGGER IF EXISTS search_track_fields ON tracks;
DROP FUNCTION IF EXISTS songspot_search_event();
DROP FUNCTION IF EXISTS songspot_search_track_fields();
DROP FUNCTION IF EXISTS songspot_search_text(text);
'''


def forward(apps, schema_editor):
    if schema_editor.connection.vendor == 'postgresql':
        schema_editor.execute(SQL)


def backward(apps, schema_editor):
    if schema_editor.connection.vendor == 'postgresql':
        schema_editor.execute(REVERSE)


class Migration(migrations.Migration):
    dependencies = [('game', '0024_search_redesign')]
    operations = [migrations.RunPython(forward, backward)]
