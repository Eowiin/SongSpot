from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0023_dailygamesession_retry_fields'),
    ]

    operations = [
        migrations.AddField(
            model_name='packbundlesession',
            name='retries_used',
            field=models.PositiveSmallIntegerField(default=0),
        ),
        migrations.AddField(
            model_name='packbundlesession',
            name='retry_credits',
            field=models.PositiveSmallIntegerField(default=0),
        ),
        migrations.AddField(
            model_name='packbundlesession',
            name='awaiting_retry_unlock',
            field=models.BooleanField(default=False),
        ),
    ]
