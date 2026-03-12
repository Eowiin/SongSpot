import re

from django.core.management.base import BaseCommand
from django.db.models import Q

from game.models import Track
from game.services import DeezerService


class Command(BaseCommand):
    help = 'Backfill Deezer metadata for existing tracks (genre, release year, cover, and Deezer ID)'

    def add_arguments(self, parser):
        parser.add_argument(
            '--all',
            action='store_true',
            help='Refresh all tracks, not just those missing metadata',
        )
        parser.add_argument(
            '--limit',
            type=int,
            help='Maximum number of tracks to inspect',
        )
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Show what would be updated without saving changes',
        )
        parser.add_argument(
            '--search-missing',
            action='store_true',
            help='Try a conservative Deezer search when a track has no deezer_id',
        )

    def handle(self, *args, **options):
        refresh_all = options['all']
        dry_run = options['dry_run']
        search_missing = options['search_missing']
        limit = options.get('limit')

        deezer = DeezerService()
        tracks = self._get_queryset(refresh_all)
        if limit:
            tracks = tracks[:limit]

        total_tracks = tracks.count()
        if total_tracks == 0:
            self.stdout.write(self.style.WARNING('No tracks need metadata updates.'))
            return

        self.stdout.write(
            self.style.WARNING(
                f'{"[DRY RUN] " if dry_run else ""}'
                f'Updating metadata for {total_tracks} track(s)...'
            )
        )

        updated = 0
        skipped = 0
        failed = 0

        for track in tracks:
            try:
                raw_track_data = None

                if track.deezer_id:
                    raw_track_data = deezer.get_track(track.deezer_id)
                if not raw_track_data and search_missing:
                    raw_track_data = self._find_search_match(deezer, track)

                if not raw_track_data:
                    skipped += 1
                    self.stdout.write(
                        self.style.WARNING(
                            f'  Skipped: {track.title} - {track.artist} (no Deezer match)'
                        )
                    )
                    continue

                track_info = deezer.enrich_track_info(raw_track_data, fallback_genre=track.genre)
                update_fields = []
                proposed_updates = {
                    'deezer_id': track_info.get('deezer_id'),
                    'cover_url': track_info.get('cover_url'),
                    'release_year': track_info.get('release_year'),
                    'genre': track_info.get('genre'),
                }

                for field, new_value in proposed_updates.items():
                    if not new_value:
                        continue

                    current_value = getattr(track, field)
                    should_update = refresh_all or current_value in (None, '')
                    if should_update and current_value != new_value:
                        setattr(track, field, new_value)
                        update_fields.append(field)

                if not update_fields:
                    skipped += 1
                    self.stdout.write(
                        self.style.WARNING(
                            f'  Skipped: {track.title} - {track.artist} (already complete)'
                        )
                    )
                    continue

                if not dry_run:
                    track.save(update_fields=update_fields)

                updated += 1
                self.stdout.write(
                    self.style.SUCCESS(
                        f'  {"[DRY RUN] " if dry_run else ""}'
                        f'Updated: {track.title} - {track.artist} ({", ".join(update_fields)})'
                    )
                )
            except Exception as exc:
                failed += 1
                self.stdout.write(
                    self.style.ERROR(
                        f'  Failed: {track.title} - {track.artist} ({exc})'
                    )
                )

        self.stdout.write('')
        self.stdout.write(self.style.SUCCESS('Completed!'))
        self.stdout.write(f'  Updated: {updated}')
        self.stdout.write(f'  Skipped: {skipped}')
        self.stdout.write(f'  Failed:  {failed}')

    @staticmethod
    def _get_queryset(refresh_all):
        queryset = Track.objects.order_by('created_at')
        if refresh_all:
            return queryset

        return queryset.filter(
            Q(deezer_id__isnull=True) |
            Q(cover_url__isnull=True) |
            Q(cover_url='') |
            Q(release_year__isnull=True) |
            Q(genre__isnull=True) |
            Q(genre='')
        )

    def _find_search_match(self, deezer, track):
        result = deezer.search_track(f'{track.title} {track.artist}', limit=10)
        candidates = result.get('data', []) if isinstance(result, dict) else []
        wanted_title = self._normalize(track.title)
        wanted_artist = self._normalize(track.artist)

        for candidate in candidates:
            candidate_title = self._normalize(candidate.get('title', ''))
            candidate_artist = self._normalize(candidate.get('artist', {}).get('name', ''))
            if candidate_title == wanted_title and candidate_artist == wanted_artist:
                return candidate

        return None

    @staticmethod
    def _normalize(value):
        return re.sub(r'[^a-z0-9]+', '', value.lower())
