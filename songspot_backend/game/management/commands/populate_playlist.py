"""
Populate a playlist with tracks from the existing track library.

Usage examples:
  # See all Deezer genre tags in the DB
  python manage.py populate_playlist --list-genres

  # Preview what would be added (no changes made)
  python manage.py populate_playlist hiphop --genre "Rap/Hip Hop" --dry-run
  python manage.py populate_playlist hiphop --artist "Drake" --dry-run

  # Add tracks by Deezer genre tag
  python manage.py populate_playlist hiphop --genre "Rap/Hip Hop"

  # Add tracks by artist name (case-insensitive)
  python manage.py populate_playlist hiphop --artist "Drake"
  python manage.py populate_playlist hiphop --artist "Kendrick Lamar"

  # Combine: genre + artist filter (e.g. only R&B tracks by a specific artist)
  python manage.py populate_playlist rnb --genre "R&B" --artist "The Weeknd"
"""
from django.core.management.base import BaseCommand, CommandError
from django.db.models import Count

from game.models import Playlist, PlaylistTrack, Track, CATEGORY_CHOICES


CATEGORY_DISPLAY = dict(CATEGORY_CHOICES)


class Command(BaseCommand):
    help = 'Add tracks to a playlist by Deezer genre tag or artist name.'

    def add_arguments(self, parser):
        parser.add_argument(
            'category', nargs='?',
            help='Playlist category key (e.g. hiphop, pop, rock). Omit to use --list-genres.',
        )
        parser.add_argument('--genre', help='Deezer genre tag to match (e.g. "Rap/Hip Hop")')
        parser.add_argument('--artist', help='Artist name to match (case-insensitive, partial ok)')
        parser.add_argument(
            '--dry-run', action='store_true',
            help='Preview tracks that would be added without making changes.',
        )
        parser.add_argument(
            '--list-genres', action='store_true',
            help='List all Deezer genre tags currently in the track library.',
        )

    def handle(self, *args, **options):
        if options['list_genres']:
            self._list_genres()
            return

        category = options['category']
        if not category:
            raise CommandError('Provide a category key, or use --list-genres. Run with --help for examples.')

        valid_keys = [k for k, _ in CATEGORY_CHOICES]
        if category not in valid_keys:
            raise CommandError(
                f'Unknown category "{category}". Valid keys: {", ".join(valid_keys)}'
            )

        genre_filter = options['genre']
        artist_filter = options['artist']
        dry_run = options['dry_run']

        if not genre_filter and not artist_filter:
            raise CommandError('Provide at least --genre or --artist (or both).')

        try:
            playlist = Playlist.objects.get(category=category)
        except Playlist.DoesNotExist:
            raise CommandError(
                f'No playlist found for category "{category}". Run reset_playlists first.'
            )

        # Build track queryset
        qs = Track.objects.filter(preview_url__isnull=False).exclude(preview_url='')
        if genre_filter:
            qs = qs.filter(genre__iexact=genre_filter)
        if artist_filter:
            qs = qs.filter(artist__icontains=artist_filter)

        tracks = list(qs.order_by('artist', 'title'))

        if not tracks:
            self.stdout.write(self.style.WARNING('No tracks found matching your filters.'))
            return

        # Find which are already in the playlist
        existing_ids = set(
            PlaylistTrack.objects.filter(playlist=playlist)
            .values_list('track_id', flat=True)
        )
        to_add = [t for t in tracks if t.id not in existing_ids]
        already_present = len(tracks) - len(to_add)

        self.stdout.write(
            f'\nPlaylist: {self.style.SUCCESS(playlist.name)}'
        )
        self.stdout.write(f'Tracks found: {len(tracks)} | Already in playlist: {already_present} | To add: {len(to_add)}')

        if not to_add:
            self.stdout.write(self.style.WARNING('Nothing new to add.'))
            return

        # Show preview table
        self.stdout.write('')
        self.stdout.write(f'{"Artist":<35} {"Title":<45} {"Year":<6} {"Genre"}')
        self.stdout.write('-' * 100)
        for t in to_add:
            artist = (t.artist or '')[:34]
            title = (t.title or '')[:44]
            year = str(t.release_year) if t.release_year else '—'
            genre = t.genre or '—'
            self.stdout.write(f'{artist:<35} {title:<45} {year:<6} {genre}')

        if dry_run:
            self.stdout.write('')
            self.stdout.write(self.style.WARNING(f'Dry run — {len(to_add)} tracks would be added. Remove --dry-run to apply.'))
            return

        # Determine starting order
        current_max = (
            PlaylistTrack.objects.filter(playlist=playlist)
            .order_by('-order_in_playlist')
            .values_list('order_in_playlist', flat=True)
            .first() or 0
        )
        PlaylistTrack.objects.bulk_create([
            PlaylistTrack(playlist=playlist, track=t, order_in_playlist=current_max + i + 1)
            for i, t in enumerate(to_add)
        ])
        self.stdout.write('')
        self.stdout.write(self.style.SUCCESS(
            f'Added {len(to_add)} tracks to "{playlist.name}".'
        ))

    def _list_genres(self):
        rows = (
            Track.objects
            .exclude(genre__isnull=True)
            .exclude(genre='')
            .values('genre')
            .annotate(n=Count('id'))
            .order_by('-n')
        )
        self.stdout.write(f'\n{"Deezer genre tag":<40} {"Track count"}')
        self.stdout.write('-' * 55)
        for row in rows:
            self.stdout.write(f'{row["genre"]:<40} {row["n"]}')
        self.stdout.write('')
