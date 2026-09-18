from django.core.management.base import BaseCommand
from game.services.search_index import rebuild


class Command(BaseCommand):
    help = 'Build and atomically activate a new local search generation; keep the previous generation.'

    def handle(self, *args, **options):
        self.stdout.write(str(rebuild()))
