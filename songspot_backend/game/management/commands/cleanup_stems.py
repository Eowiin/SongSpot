from django.core.management.base import BaseCommand


class Command(BaseCommand):
    help = 'Removed — stem generation no longer used.'

    def handle(self, *args, **options):
        self.stdout.write('Stem cleanup is no longer applicable in the new architecture.')
