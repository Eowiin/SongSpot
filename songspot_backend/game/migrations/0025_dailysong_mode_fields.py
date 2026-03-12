from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0024_packbundlesession_retry_fields'),
    ]

    operations = [
        migrations.AddField(
            model_name='dailysong',
            name='genre_key',
            field=models.CharField(blank=True, choices=[('pop', 'Pop'), ('hiphop', 'Hip-Hop / Rap'), ('rock', 'Rock'), ('electro', 'Électro'), ('dance', 'Dance'), ('rnb', 'R&B'), ('kpop', 'K-pop'), ('rap_fr', 'Rap Français'), ('variete_fr', 'Variété Française'), ('reggaeton', 'Reggaeton / Urbano'), ('latin', 'Latin Pop'), ('afrobeats', 'Afrobeats'), ('jpop', 'J-pop'), ('bollywood', 'Bollywood')], help_text='Category key for genre dailies', max_length=20, null=True),
        ),
        migrations.AddField(
            model_name='dailysong',
            name='genre_name',
            field=models.CharField(blank=True, help_text='Display name for genre dailies', max_length=100, null=True),
        ),
        migrations.AddField(
            model_name='dailysong',
            name='mode',
            field=models.CharField(choices=[('mix', 'Daily Mix'), ('genre', 'Daily Genre')], default='mix', help_text='Daily challenge mode for this selection', max_length=10),
        ),
        migrations.AlterUniqueTogether(
            name='dailysong',
            unique_together={('room', 'date', 'mode')},
        ),
        migrations.RemoveIndex(
            model_name='dailysong',
            name='daily_songs_room_id_5a76dd_idx',
        ),
        migrations.AddIndex(
            model_name='dailysong',
            index=models.Index(fields=['room', 'date', 'mode'], name='daily_songs_room_id_b762e8_idx'),
        ),
    ]
