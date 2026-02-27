from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('authentication', '0004_coinproduct_alter_cointransaction_transaction_type_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='user',
            name='ad_free_until',
            field=models.DateTimeField(
                blank=True,
                help_text='When set in the future, ads are disabled for this user',
                null=True,
            ),
        ),
    ]

