from django.core.management.base import BaseCommand
from game.models import Track
from ._artist_utils import is_variant_title


class Command(BaseCommand):
    help = 'Remove remastered, live, acoustic, demo and similar variant tracks from the database'

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            default=False,
            help='Preview what would be deleted without actually deleting',
        )

    def handle(self, *args, **options):
        dry_run = options['dry_run']

        variants = [t for t in Track.objects.only('id', 'title', 'artist') if is_variant_title(t.title)]

        if not variants:
            self.stdout.write(self.style.SUCCESS('No variant tracks found.'))
            return

        self.stdout.write(self.style.WARNING(
            f'{"[DRY RUN] " if dry_run else ""}Found {len(variants)} variant track(s):'
        ))
        for track in variants:
            self.stdout.write(f'  - {track.artist} — {track.title}')

        if dry_run:
            self.stdout.write(self.style.WARNING(
                f'\n[DRY RUN] {len(variants)} tracks would be deleted. Run without --dry-run to apply.'
            ))
            return

        ids = [t.id for t in variants]
        deleted, _ = Track.objects.filter(id__in=ids).delete()
        self.stdout.write(self.style.SUCCESS(
            f'\nDeleted {deleted} variant track(s) (PlaylistTrack entries removed by cascade).'
        ))
        self.stdout.write(self.style.SUCCESS(
            f'Tracks remaining in database: {Track.objects.count()}'
        ))
