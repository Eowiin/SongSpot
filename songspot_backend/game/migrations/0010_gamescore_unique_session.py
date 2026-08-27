from django.db import migrations, models


def drop_duplicate_session_scores(apps, schema_editor):
    """Keep the most recent GameScore per (user, session_uuid), drop the rest.

    Concurrent submits from the same session (a partial checkpoint racing the
    final score) could each insert a row; the survivors are what the unique
    constraint below then enforces.
    """
    GameScore = apps.get_model('game', 'GameScore')
    duplicates = (
        GameScore.objects
        .filter(session_uuid__isnull=False)
        .values('user_id', 'session_uuid')
        .annotate(n=models.Count('id'))
        .filter(n__gt=1)
    )
    for group in duplicates:
        keep = (
            GameScore.objects
            .filter(user_id=group['user_id'], session_uuid=group['session_uuid'])
            .order_by('-played_at')
            .values_list('id', flat=True)
            .first()
        )
        (GameScore.objects
         .filter(user_id=group['user_id'], session_uuid=group['session_uuid'])
         .exclude(id=keep)
         .delete())


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0009_checkpoint_fields'),
    ]

    operations = [
        migrations.RunPython(
            drop_duplicate_session_scores,
            migrations.RunPython.noop,
        ),
        migrations.AddConstraint(
            model_name='gamescore',
            constraint=models.UniqueConstraint(
                condition=models.Q(('session_uuid__isnull', False)),
                fields=('user', 'session_uuid'),
                name='uniq_gamescore_user_session',
            ),
        ),
    ]
