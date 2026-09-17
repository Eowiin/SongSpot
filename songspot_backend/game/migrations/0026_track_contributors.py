from django.db import migrations, models


def trigger(schema_editor, include):
    if schema_editor.connection.vendor == 'postgresql':
        extra = ', contributors' if include else ''
        schema_editor.execute('DROP TRIGGER search_track_event ON tracks')
        schema_editor.execute(f'''CREATE TRIGGER search_track_event AFTER INSERT OR DELETE OR UPDATE OF
            title, artist, rank, deezer_artist_id{extra} ON tracks
            FOR EACH ROW EXECUTE FUNCTION songspot_search_event()''')


def forward(apps, schema_editor):
    trigger(schema_editor, True)


def backward(apps, schema_editor):
    trigger(schema_editor, False)


class Migration(migrations.Migration):
    dependencies = [('game', '0025_search_triggers')]
    operations = [
        migrations.AddField(model_name='track', name='contributors', field=models.JSONField(default=list, blank=True)),
        migrations.RunPython(forward, backward),
    ]
