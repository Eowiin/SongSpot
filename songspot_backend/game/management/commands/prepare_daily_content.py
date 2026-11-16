from typing import Any

from django.core.management.base import BaseCommand


class Command(BaseCommand):
    help = 'Removed — daily content preparation no longer used.'

    def handle(self, *args: Any, **options: Any) -> None:
        self.stdout.write('Daily content preparation is no longer applicable in the new architecture.')
