from django.core.management.base import BaseCommand
from game.models import Track
from game.services import DeezerService


class Command(BaseCommand):
    help = 'Fetch random tracks from Deezer API and save to database'

    def add_arguments(self, parser):
        parser.add_argument(
            '--count',
            type=int,
            default=50,
            help='Number of tracks to fetch (default: 50)',
        )

    def handle(self, *args, **options):
        count = options['count']
        deezer = DeezerService()

        self.stdout.write(self.style.WARNING(f'Fetching {count} tracks from Deezer...'))

        tracks_fetched = 0
        tracks_skipped = 0

        # Fetch random tracks
        track_data_list = deezer.get_random_tracks(count=count)

        for track_data in track_data_list:
            track_info = deezer.extract_track_info(track_data)

            # Skip if no preview URL
            if not track_info['preview_url']:
                tracks_skipped += 1
                continue

            # Check if track already exists (by title and artist)
            existing_track = Track.objects.filter(
                title=track_info['title'],
                artist=track_info['artist']
            ).first()

            if existing_track:
                self.stdout.write(
                    self.style.WARNING(
                        f'  Skipped: {track_info["title"]} - {track_info["artist"]} (already exists)'
                    )
                )
                tracks_skipped += 1
                continue

            # Create new track
            Track.objects.create(
                title=track_info['title'],
                artist=track_info['artist'],
                preview_url=track_info['preview_url'],
                deezer_id=track_info.get('deezer_id')
            )

            self.stdout.write(
                self.style.SUCCESS(
                    f'  ✓ Added: {track_info["title"]} - {track_info["artist"]}'
                )
            )
            tracks_fetched += 1

        self.stdout.write(
            self.style.SUCCESS(
                f'\nCompleted! {tracks_fetched} tracks added, {tracks_skipped} skipped'
            )
        )
        self.stdout.write(
            self.style.SUCCESS(
                f'Total tracks in database: {Track.objects.count()}'
            )
        )
