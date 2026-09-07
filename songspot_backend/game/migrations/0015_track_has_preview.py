"""
Replace the stored preview URL with a flag.

Deezer signs preview URLs with a fifteen-minute expiry, so a URL in this table
is expired every time it is read — the column was 266 bytes of the average row
(measured), roughly half of it, spent on data that never worked. All the game
needs from the database is whether audio exists at all; the URL itself is
resolved at play time from a shared container pool. See services/previews.

The generated migration dropped the column before adding the flag, which would
have thrown away the only information there was to migrate. Order matters here:
add, backfill, then drop.
"""

from django.db import migrations, models


def backfill_has_preview(apps, schema_editor):
    """Every row that held a URL had audio, whether or not that URL still works."""
    Track = apps.get_model('game', 'Track')
    Track.objects.exclude(preview_url='').exclude(preview_url__isnull=True).update(
        has_preview=True,
    )


def restore_preview_url(apps, schema_editor):
    """
    Reversing this cannot bring the URLs back, and should not pretend to.

    They were expired anyway; a re-import repopulates `has_preview` on its own.
    """


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0014_trigram_search_indexes'),
    ]

    operations = [
        migrations.AddField(
            model_name='track',
            name='has_preview',
            field=models.BooleanField(default=False),
        ),
        migrations.RunPython(backfill_has_preview, restore_preview_url),
        migrations.RemoveField(model_name='track', name='preview_url'),
    ]
