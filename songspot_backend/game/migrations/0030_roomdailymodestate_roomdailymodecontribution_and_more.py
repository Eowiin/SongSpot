from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0029_roommessage_mode'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='RoomDailyModeState',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('mode', models.CharField(choices=[('mix', 'Daily Mix'), ('genre', 'Daily Genre'), ('decade', 'Daily Decade'), ('hardcore', 'Hardcore')], max_length=20)),
                ('progress_coins', models.PositiveIntegerField(default=0)),
                ('unlocked_for_date', models.DateField(blank=True, null=True)),
                ('last_unlocked_at', models.DateTimeField(blank=True, null=True)),
                ('last_unlock_contributor_count', models.PositiveIntegerField(default=0)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('room', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='daily_mode_states', to='game.room')),
            ],
            options={
                'db_table': 'room_daily_mode_states',
                'ordering': ['room_id', 'mode'],
                'indexes': [models.Index(fields=['room', 'mode'], name='room_daily__room_id_4ba8c8_idx')],
                'unique_together': {('room', 'mode')},
            },
        ),
        migrations.CreateModel(
            name='RoomDailyModeContribution',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('amount', models.PositiveIntegerField(default=0)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('state', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='contributions', to='game.roomdailymodestate')),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='daily_mode_contributions', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'room_daily_mode_contributions',
                'ordering': ['created_at'],
                'indexes': [models.Index(fields=['state', 'user'], name='room_daily__state_i_8c2037_idx')],
                'unique_together': {('state', 'user')},
            },
        ),
        migrations.AlterField(
            model_name='dailysong',
            name='mode',
            field=models.CharField(choices=[('mix', 'Daily Mix'), ('genre', 'Daily Genre'), ('decade', 'Daily Decade'), ('hardcore', 'Hardcore')], default='mix', help_text='Daily challenge mode for this selection', max_length=10),
        ),
        migrations.AlterField(
            model_name='roommessage',
            name='mode',
            field=models.CharField(choices=[('mix', 'Daily Mix'), ('genre', 'Daily Genre'), ('decade', 'Daily Decade'), ('hardcore', 'Hardcore')], default='mix', max_length=10),
        ),
    ]
