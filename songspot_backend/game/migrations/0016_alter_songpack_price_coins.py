from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0015_packbundlestemjob'),
    ]

    operations = [
        migrations.AlterField(
            model_name='songpack',
            name='price_coins',
            field=models.PositiveIntegerField(default=600, help_text='Price in coins'),
        ),
    ]
