from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0021_alter_songpack_category'),
    ]

    operations = [
        migrations.RemoveField(
            model_name='songpack',
            name='is_featured',
        ),
        migrations.AlterModelOptions(
            name='songpack',
            options={'ordering': ['name']},
        ),
    ]
