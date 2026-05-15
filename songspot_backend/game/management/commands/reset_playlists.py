from django.core.management.base import BaseCommand
from game.models import Playlist, CATEGORY_CHOICES


class Command(BaseCommand):
    help = 'Delete all playlists and create one empty playlist per genre category.'

    def handle(self, *args, **options):
        deleted_count, _ = Playlist.objects.all().delete()

        created = 0
        for key, display_name in CATEGORY_CHOICES:
            if not Playlist.objects.filter(category=key).exists():
                Playlist.objects.create(name=display_name, category=key)
                created += 1

        self.stdout.write(self.style.SUCCESS(
            f'Deleted {deleted_count} playlists. Created {created} playlists.'
        ))
