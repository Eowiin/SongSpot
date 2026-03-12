from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0027_rename_daily_songs_room_id_b762e8_idx_daily_songs_room_id_4d94d8_idx'),
    ]

    operations = [
        migrations.AddField(
            model_name='roompack',
            name='activated_on',
            field=models.DateField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='roompack',
            name='completed_on',
            field=models.DateField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='roompack',
            name='is_active',
            field=models.BooleanField(default=False),
        ),
        migrations.AddConstraint(
            model_name='roompack',
            constraint=models.UniqueConstraint(
                condition=models.Q(('is_active', True)),
                fields=('room',),
                name='unique_active_room_pack_per_room',
            ),
        ),
    ]
