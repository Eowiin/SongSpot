from django.db import migrations, models
from django.db.models import Q


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0025_dailysong_mode_fields'),
    ]

    operations = [
        migrations.AddField(
            model_name='packbundlemessage',
            name='client_message_id',
            field=models.CharField(blank=True, max_length=64, null=True),
        ),
        migrations.AddField(
            model_name='roommessage',
            name='client_message_id',
            field=models.CharField(blank=True, max_length=64, null=True),
        ),
        migrations.AddConstraint(
            model_name='packbundlemessage',
            constraint=models.UniqueConstraint(
                condition=Q(client_message_id__isnull=False),
                fields=('room', 'pack', 'pack_daily_track', 'user', 'client_message_id'),
                name='pack_bundle_message_client_id_unique',
            ),
        ),
        migrations.AddConstraint(
            model_name='roommessage',
            constraint=models.UniqueConstraint(
                condition=Q(client_message_id__isnull=False),
                fields=('room', 'user', 'client_message_id'),
                name='room_message_client_id_unique',
            ),
        ),
    ]
