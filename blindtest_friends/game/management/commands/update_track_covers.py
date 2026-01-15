from django.core.management.base import BaseCommand
from game.models import Track
from game.services import DeezerService


class Command(BaseCommand):
    help = 'Update existing tracks with cover URLs from Deezer API'

    def add_arguments(self, parser):
        parser.add_argument(
            '--all',
            action='store_true',
            help='Update all tracks, not just those missing cover URLs',
        )

    def handle(self, *args, **options):
        update_all = options['all']
        deezer = DeezerService()

        # Get tracks to update
        if update_all:
            tracks = Track.objects.filter(deezer_id__isnull=False)
            self.stdout.write(self.style.WARNING(f'Updating cover URLs for all {tracks.count()} tracks with deezer_id...'))
        else:
            tracks = Track.objects.filter(deezer_id__isnull=False, cover_url__isnull=True)
            self.stdout.write(self.style.WARNING(f'Updating cover URLs for {tracks.count()} tracks missing covers...'))

        updated = 0
        failed = 0

        for track in tracks:
            track_data = deezer.get_track(track.deezer_id)

            if track_data:
                track_info = deezer.extract_track_info(track_data)
                cover_url = track_info.get('cover_url')

                if cover_url:
                    track.cover_url = cover_url
                    track.save(update_fields=['cover_url'])
                    self.stdout.write(
                        self.style.SUCCESS(f'  ✓ Updated: {track.title} - {track.artist}')
                    )
                    updated += 1
                else:
                    self.stdout.write(
                        self.style.WARNING(f'  ⚠ No cover found: {track.title} - {track.artist}')
                    )
                    failed += 1
            else:
                self.stdout.write(
                    self.style.ERROR(f'  ✗ API error: {track.title} - {track.artist}')
                )
                failed += 1

        self.stdout.write(
            self.style.SUCCESS(f'\nCompleted! {updated} tracks updated, {failed} failed')
        )
