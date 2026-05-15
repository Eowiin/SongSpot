import time

from django.core.management.base import BaseCommand

from game.models import Track
from game.services import DeezerService


class Command(BaseCommand):
    help = 'Backfill artist_picture_url for existing tracks using Deezer API'

    def add_arguments(self, parser):
        parser.add_argument(
            '--delay',
            type=float,
            default=0.1,
            help='Seconds to wait between Deezer requests (default: 0.1)',
        )

    def handle(self, *args, **options):
        delay = options['delay']
        deezer = DeezerService()

        # One representative track per artist that is missing a picture
        artists_missing = (
            Track.objects
            .filter(artist_picture_url__isnull=True, deezer_id__isnull=False)
            .values('artist')
            .distinct()
        )
        artist_names = [row['artist'] for row in artists_missing]

        total = len(artist_names)
        self.stdout.write(f'Artists to backfill: {total}')

        updated = 0
        failed = 0

        for i, artist_name in enumerate(artist_names, 1):
            try:
                artist_data = deezer.search_artist(artist_name)
                if not artist_data:
                    failed += 1
                    self.stdout.write(self.style.WARNING(f'[{i}/{total}] not found: {artist_name}'))
                    continue

                artist_detail = deezer.get_artist(artist_data['id']) or {}
                picture_url = (
                    artist_detail.get('picture_xl') or
                    artist_detail.get('picture_big') or
                    artist_detail.get('picture_medium') or
                    artist_detail.get('picture_small') or
                    artist_detail.get('picture')
                )

                if picture_url:
                    Track.objects.filter(artist=artist_name).update(
                        artist_picture_url=picture_url
                    )
                    updated += 1
                    self.stdout.write(f'[{i}/{total}] ✓ {artist_name}')
                else:
                    failed += 1
                    self.stdout.write(self.style.WARNING(f'[{i}/{total}] no picture: {artist_name}'))

            except Exception as e:
                failed += 1
                self.stdout.write(self.style.ERROR(f'[{i}/{total}] error for {artist_name}: {e}'))

            if delay:
                time.sleep(delay)

        self.stdout.write(self.style.SUCCESS(
            f'\nDone. {updated} artists updated, {failed} failed/skipped.'
        ))
