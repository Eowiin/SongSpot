from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion
import uuid


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0013_packdailytrack_and_more'),
    ]

    operations = [
        migrations.CreateModel(
            name='PackBundleMessage',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('message', models.TextField(max_length=500)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('pack', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='bundle_messages', to='game.songpack')),
                ('pack_daily_track', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='bundle_messages', to='game.packdailytrack')),
                ('room', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='pack_bundle_messages', to='game.room')),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='pack_bundle_messages', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'pack_bundle_messages',
                'ordering': ['-created_at'],
            },
        ),
        migrations.AddIndex(
            model_name='packbundlemessage',
            index=models.Index(fields=['pack_daily_track', 'created_at'], name='pack_bundle_pack_d_76f8f6_idx'),
        ),
        migrations.AddIndex(
            model_name='packbundlemessage',
            index=models.Index(fields=['room', 'pack'], name='pack_bundle_room_id_6c17d1_idx'),
        ),
    ]
