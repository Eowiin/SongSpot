from django.db import migrations, models


def mark_playlist_tracks_curated(apps, schema_editor):
    """
    Anything already sitting in a category came from a curated source.

    Either the original hand-picked seed list or a chart refresh — both are the
    provenance this flag records. Without the backfill, tracks imported before
    the column existed would be judged on their raw Deezer rank alone, which is
    exactly the euro-centric filter the flag exists to bypass.
    """
    Track = apps.get_model('game', 'Track')
    PlaylistTrack = apps.get_model('game', 'PlaylistTrack')
    track_ids = list(
        PlaylistTrack.objects.values_list('track_id', flat=True).distinct()
    )
    Track.objects.filter(id__in=track_ids).update(is_curated=True)


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0011_open_catalog'),
    ]

    operations = [
        migrations.AddField(
            model_name='track',
            name='is_curated',
            field=models.BooleanField(db_index=True, default=False),
        ),
        migrations.RunPython(
            mark_playlist_tracks_curated, migrations.RunPython.noop, elidable=False,
        ),
    ]
