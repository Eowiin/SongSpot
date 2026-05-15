import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0005_track_artist_picture_url'),
    ]

    operations = [
        # Rename models (Django state only — db_table is explicit so table stays unchanged)
        migrations.RenameModel('SongPack', 'Playlist'),
        migrations.RenameModel('PackTrack', 'PlaylistTrack'),

        # Rename database tables
        migrations.AlterModelTable('Playlist', 'playlists'),
        migrations.AlterModelTable('PlaylistTrack', 'playlist_tracks'),

        # Drop old index before renaming the columns it references
        migrations.RemoveIndex(
            model_name='playlisttrack',
            name='pack_tracks_pack_id_a56cd4_idx',
        ),

        # Rename fields (also renames the underlying DB columns)
        migrations.RenameField('PlaylistTrack', 'pack', 'playlist'),
        migrations.RenameField('PlaylistTrack', 'order_in_pack', 'order_in_playlist'),

        # Update unique constraint to reference the renamed field
        migrations.AlterUniqueTogether(
            name='playlisttrack',
            unique_together={('playlist', 'track')},
        ),

        # Update ordering option
        migrations.AlterModelOptions(
            name='playlisttrack',
            options={'ordering': ['order_in_playlist']},
        ),

        # Update related_names on both FKs
        migrations.AlterField(
            model_name='playlisttrack',
            name='playlist',
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.CASCADE,
                related_name='playlist_tracks',
                to='game.playlist',
            ),
        ),
        migrations.AlterField(
            model_name='playlisttrack',
            name='track',
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.CASCADE,
                related_name='in_playlists',
                to='game.track',
            ),
        ),

        # Add new index with updated column names
        migrations.AddIndex(
            model_name='playlisttrack',
            index=models.Index(
                fields=['playlist', 'order_in_playlist'],
                name='playlist_tracks_playlist_id_idx',
            ),
        ),
    ]
