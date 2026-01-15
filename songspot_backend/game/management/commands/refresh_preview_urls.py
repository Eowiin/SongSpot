from django.core.management.base import BaseCommand
from game.models import Track
from game.services import DeezerService


class Command(BaseCommand):
    help = 'Refresh preview URLs for all tracks that have a Deezer ID'

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Show what would be updated without making changes',
        )

    def handle(self, *args, **options):
        dry_run = options['dry_run']
        deezer = DeezerService()

        # Get all tracks with deezer_id
        tracks_with_deezer_id = Track.objects.filter(deezer_id__isnull=False)
        total_tracks = tracks_with_deezer_id.count()

        if total_tracks == 0:
            self.stdout.write(
                self.style.WARNING('No tracks with Deezer ID found. Run fetch_deezer_tracks first.')
            )
            return

        self.stdout.write(
            self.style.WARNING(f'{"[DRY RUN] " if dry_run else ""}Refreshing preview URLs for {total_tracks} tracks...')
        )

        updated = 0
        failed = 0
        skipped = 0

        for track in tracks_with_deezer_id:
            try:
                # Fetch fresh track data from Deezer
                track_data = deezer.get_track(track.deezer_id)

                if track_data and track_data.get('preview'):
                    new_preview_url = track_data['preview']

                    if new_preview_url == track.preview_url:
                        skipped += 1
                        self.stdout.write(
                            self.style.WARNING(
                                f'  → Skipped: {track.title[:40]} (URL unchanged)'
                            )
                        )
                        continue

                    if not dry_run:
                        track.preview_url = new_preview_url
                        track.save(update_fields=['preview_url'])

                    self.stdout.write(
                        self.style.SUCCESS(
                            f'  ✓ {"[DRY RUN] " if dry_run else ""}Updated: {track.title[:40]}'
                        )
                    )
                    updated += 1
                else:
                    self.stdout.write(
                        self.style.ERROR(
                            f'  ✗ Failed: {track.title[:40]} (No preview URL from Deezer)'
                        )
                    )
                    failed += 1

            except Exception as e:
                self.stdout.write(
                    self.style.ERROR(
                        f'  ✗ Error for {track.title[:40]}: {str(e)}'
                    )
                )
                failed += 1

        # Summary
        self.stdout.write('')
        self.stdout.write(
            self.style.SUCCESS(
                f'{"[DRY RUN] " if dry_run else ""}Completed!'
            )
        )
        self.stdout.write(f'  • Updated: {updated}')
        self.stdout.write(f'  • Skipped: {skipped} (unchanged)')
        self.stdout.write(f'  • Failed:  {failed}')
        self.stdout.write(f'  • Total:   {total_tracks}')

        if dry_run:
            self.stdout.write('')
            self.stdout.write(
                self.style.WARNING(
                    'This was a dry run. Run without --dry-run to actually update the database.'
                )
            )
