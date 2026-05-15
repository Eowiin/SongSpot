from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0004_gamescore_difficulty'),
    ]

    operations = [
        migrations.AddField(
            model_name='track',
            name='artist_picture_url',
            field=models.URLField(blank=True, max_length=500, null=True),
        ),
    ]
