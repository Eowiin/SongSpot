from django.db import migrations, models
import django.db.models.deletion
import uuid


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0014_packbundlemessage'),
    ]

    operations = [
        migrations.CreateModel(
            name='PackBundleStemJob',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('status', models.CharField(choices=[('queued', 'Queued'), ('running', 'Running'), ('ready', 'Ready'), ('failed', 'Failed')], default='queued', max_length=20)),
                ('error_message', models.TextField(blank=True)),
                ('started_at', models.DateTimeField(blank=True, null=True)),
                ('completed_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('pack_track', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name='stem_job', to='game.packtrack')),
            ],
            options={
                'db_table': 'pack_bundle_stem_jobs',
            },
        ),
        migrations.AddIndex(
            model_name='packbundlestemjob',
            index=models.Index(fields=['status', 'created_at'], name='pack_bundle_status_3a62cf_idx'),
        ),
    ]
