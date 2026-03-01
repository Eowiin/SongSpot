from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0022_remove_songpack_is_featured'),
    ]

    operations = [
        migrations.AddField(
            model_name='dailygamesession',
            name='retries_used',
            field=models.PositiveSmallIntegerField(default=0),
        ),
        migrations.AddField(
            model_name='dailygamesession',
            name='retry_credits',
            field=models.PositiveSmallIntegerField(default=0),
        ),
        migrations.AddField(
            model_name='dailygamesession',
            name='awaiting_retry_unlock',
            field=models.BooleanField(default=False),
        ),
    ]
