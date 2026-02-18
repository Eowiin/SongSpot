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

        if count <= 0:
            self.stdout.write(self.style.WARNING('Count must be greater than 0. Nothing to fetch.'))
            return

        self.stdout.write(self.style.WARNING(f'Fetching {count} tracks from Deezer...'))

        tracks_fetched = 0
        tracks_skipped = 0
        max_rounds = 6

        for round_num in range(1, max_rounds + 1):
            if tracks_fetched >= count:
                break

            remaining = count - tracks_fetched
            batch_count = min(max(remaining * 2, 50), 300)

            self.stdout.write(
                self.style.WARNING(
                    f'Round {round_num}/{max_rounds}: requesting {batch_count} tracks (need {remaining} more)'
                )
            )

            track_data_list = deezer.get_random_tracks(count=batch_count)
            if not track_data_list:
                self.stdout.write(self.style.WARNING('No tracks returned from Deezer in this round.'))
                continue

            added_this_round = 0

            for track_data in track_data_list:
                if tracks_fetched >= count:
                    break

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
                    cover_url=track_info.get('cover_url'),
                    deezer_id=track_info.get('deezer_id')
                )

                self.stdout.write(
                    self.style.SUCCESS(
                        f'  ✓ Added: {track_info["title"]} - {track_info["artist"]}'
                    )
                )
                tracks_fetched += 1
                added_this_round += 1

            if added_this_round == 0:
                self.stdout.write(
                    self.style.WARNING(
                        'No new tracks were added in this round; continuing with another fetch round.'
                    )
                )

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
