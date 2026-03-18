from django.db import migrations, models
from django.db.models.functions import Lower


def lowercase_existing_emails(apps, schema_editor):
    User = apps.get_model('authentication', 'User')

    normalized = {}
    for user in User.objects.all().only('id', 'email'):
        email = (user.email or '').strip().lower()
        normalized.setdefault(email, []).append(str(user.id))

    duplicates = {
        email: ids for email, ids in normalized.items()
        if email and len(ids) > 1
    }
    if duplicates:
        details = ', '.join(
            f'{email}: {", ".join(ids)}'
            for email, ids in sorted(duplicates.items())
        )
        raise RuntimeError(
            'Cannot normalize user emails to lowercase because duplicates exist: '
            f'{details}'
        )

    for user in User.objects.all().only('id', 'email'):
        email = (user.email or '').strip().lower()
        if user.email != email:
            User.objects.filter(pk=user.pk).update(email=email)


class Migration(migrations.Migration):

    dependencies = [
        ('authentication', '0007_rename_ad_reward_c_user_id_e9f122_idx_ad_reward_c_user_id_e1feb4_idx'),
    ]

    operations = [
        migrations.RunPython(
            lowercase_existing_emails,
            migrations.RunPython.noop,
        ),
        migrations.AddConstraint(
            model_name='user',
            constraint=models.UniqueConstraint(
                Lower('email'),
                name='user_email_lower_unique',
            ),
        ),
    ]
