import django.db.models.deletion
import uuid
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('authentication', '0005_user_ad_free_until'),
    ]

    operations = [
        migrations.CreateModel(
            name='AdRewardClaim',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('placement', models.CharField(default='game_result', help_text='Where the rewarded ad was watched (e.g. game_result)', max_length=50)),
                ('coins_awarded', models.PositiveSmallIntegerField(default=0)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='ad_reward_claims', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'ad_reward_claims',
                'ordering': ['-created_at'],
            },
        ),
        migrations.AddIndex(
            model_name='adrewardclaim',
            index=models.Index(fields=['user', '-created_at'], name='ad_reward_c_user_id_e9f122_idx'),
        ),
    ]

