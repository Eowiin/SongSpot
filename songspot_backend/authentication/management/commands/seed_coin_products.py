"""
Management command to seed CoinProduct records.

Usage:
    python manage.py seed_coin_products
    python manage.py seed_coin_products --clear   # wipe and re-seed
"""
from django.core.management.base import BaseCommand

from authentication.models import CoinProduct

PRODUCTS = [
    {
        'product_id': 'com.songspot.coins.500',
        'name': 'Starter Pack',
        'coins_amount': 500,
        'price_display': '$1.99',
        'bonus_label': '',
        'sort_order': 1,
    },
    {
        'product_id': 'com.songspot.coins.1200',
        'name': 'Popular Pack',
        'coins_amount': 1200,
        'price_display': '$3.99',
        'bonus_label': 'Most Popular',
        'sort_order': 2,
    },
    {
        'product_id': 'com.songspot.coins.3000',
        'name': 'Value Pack',
        'coins_amount': 3000,
        'price_display': '$7.99',
        'bonus_label': 'Best Value',
        'sort_order': 3,
    },
    {
        'product_id': 'com.songspot.coins.7000',
        'name': 'Ultimate Pack',
        'coins_amount': 7000,
        'price_display': '$14.99',
        'bonus_label': '',
        'sort_order': 4,
    },
]


class Command(BaseCommand):
    help = 'Seed CoinProduct records (idempotent — safe to run multiple times)'

    def add_arguments(self, parser):
        parser.add_argument(
            '--clear',
            action='store_true',
            help='Delete all existing CoinProducts before seeding',
        )

    def handle(self, *args, **options):
        if options['clear']:
            deleted, _ = CoinProduct.objects.all().delete()
            self.stdout.write(self.style.WARNING(f'Deleted {deleted} existing coin products.'))

        created_count = 0
        updated_count = 0

        for data in PRODUCTS:
            product_id = data.pop('product_id')
            obj, created = CoinProduct.objects.update_or_create(
                product_id=product_id,
                defaults={**data, 'is_active': True},
            )
            data['product_id'] = product_id  # restore for next iteration

            if created:
                created_count += 1
                self.stdout.write(f'  Created  {obj.product_id} ({obj.name} — {obj.coins_amount} coins)')
            else:
                updated_count += 1
                self.stdout.write(f'  Updated  {obj.product_id} ({obj.name} — {obj.coins_amount} coins)')

        self.stdout.write(self.style.SUCCESS(
            f'\nDone — {created_count} created, {updated_count} updated.'
        ))
