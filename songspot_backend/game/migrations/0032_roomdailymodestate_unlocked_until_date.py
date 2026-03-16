from datetime import timedelta

from django.db import migrations, models


def backfill_unlocked_until_dates(apps, schema_editor):
    RoomDailyModeState = apps.get_model('game', 'RoomDailyModeState')
    for state in RoomDailyModeState.objects.exclude(unlocked_for_date__isnull=True):
        if state.unlocked_until_date is not None:
            continue
        state.unlocked_until_date = state.unlocked_for_date + timedelta(days=6)
        state.save(update_fields=['unlocked_until_date'])


def clear_unlocked_until_dates(apps, schema_editor):
    RoomDailyModeState = apps.get_model('game', 'RoomDailyModeState')
    RoomDailyModeState.objects.update(unlocked_until_date=None)


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0031_rename_room_daily__state_i_8c2037_idx_room_daily__state_i_d50703_idx_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='roomdailymodestate',
            name='unlocked_until_date',
            field=models.DateField(blank=True, null=True),
        ),
        migrations.RunPython(
            backfill_unlocked_until_dates,
            clear_unlocked_until_dates,
        ),
    ]
