from django.db import migrations, models
from django.db.models import Q


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0028_roompack_activation_state'),
    ]

    operations = [
        migrations.AddField(
            model_name='roommessage',
            name='mode',
            field=models.CharField(
                choices=[('mix', 'Daily Mix'), ('genre', 'Daily Genre')],
                default='mix',
                max_length=16,
            ),
        ),
        migrations.RemoveConstraint(
            model_name='roommessage',
            name='room_message_client_id_unique',
        ),
        migrations.RemoveIndex(
            model_name='roommessage',
            name='room_messag_room_id_68de92_idx',
        ),
        migrations.AddIndex(
            model_name='roommessage',
            index=models.Index(
                fields=['room', 'mode', '-created_at'],
                name='room_messag_room_id_8e386a_idx',
            ),
        ),
        migrations.AddConstraint(
            model_name='roommessage',
            constraint=models.UniqueConstraint(
                condition=Q(client_message_id__isnull=False),
                fields=('room', 'mode', 'user', 'client_message_id'),
                name='room_message_client_id_unique',
            ),
        ),
    ]
