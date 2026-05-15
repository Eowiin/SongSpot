from django.core.management.base import BaseCommand
from game.models import Track
from game.services import DeezerService


class Command(BaseCommand):
    help = 'Fetch tracks from Deezer top artists and save to database'

    def add_arguments(self, parser):
        parser.add_argument(
            '--artists',
            type=int,
            default=200,
            help='Number of top artists to fetch (default: 200)',
        )
        parser.add_argument(
            '--tracks-per-artist',
            type=int,
            default=5,
            help='Tracks per artist (default: 5)',
        )
        parser.add_argument(
            '--max-tracks',
            type=int,
            default=400,
            help='Maximum total tracks to add (default: 400)',
        )

    def handle(self, *args, **options):
        artist_limit = options['artists']
        tracks_per_artist = max(5, options['tracks_per_artist'])
        max_tracks = options['max_tracks']

        deezer = DeezerService()
        self.stdout.write(self.style.WARNING(f'Fetching top {artist_limit} artists from Deezer...'))

        artists = deezer.get_top_artists(limit=artist_limit)
        if not artists:
            self.stdout.write(self.style.ERROR('No artists found.'))
            return

        tracks_added = 0
        tracks_skipped = 0
        tracks_updated = 0

        for artist in artists:
            if tracks_added >= max_tracks:
                break
            artist_id = artist.get('id')
            if not artist_id:
                continue
            artist_name = artist.get('name', 'Unknown')

            top_tracks = deezer.get_artist_top_tracks(artist_id, limit=tracks_per_artist)
            for track_data in top_tracks:
                if tracks_added >= max_tracks:
                    break
                track_info = deezer.enrich_track_info(track_data)

                if not track_info['preview_url']:
                    tracks_skipped += 1
                    continue

                existing_track = Track.objects.filter(
                    title=track_info['title'],
                    artist=track_info['artist']
                ).first()

                if existing_track:
                    update_fields = []
                    for field in ('cover_url', 'deezer_id', 'release_year', 'genre'):
                        new_value = track_info.get(field)
                        if not new_value:
                            continue
                        current_value = getattr(existing_track, field)
                        if current_value in (None, ''):
                            setattr(existing_track, field, new_value)
                            update_fields.append(field)

                    if update_fields:
                        existing_track.save(update_fields=update_fields)
                        tracks_updated += 1
                    tracks_skipped += 1
                    continue

                Track.objects.create(
                    title=track_info['title'],
                    artist=track_info['artist'],
                    preview_url=track_info['preview_url'],
                    cover_url=track_info.get('cover_url'),
                    deezer_id=track_info.get('deezer_id'),
                    release_year=track_info.get('release_year'),
                    genre=track_info.get('genre'),
                    artist_picture_url=track_info.get('artist_picture_url'),
                )
                tracks_added += 1

            self.stdout.write(self.style.SUCCESS(
                f'Processed artist: {artist_name}'
            ))

        self.stdout.write(self.style.SUCCESS(
            f'\nCompleted! {tracks_added} tracks added, {tracks_updated} updated, {tracks_skipped} skipped'
        ))
        self.stdout.write(self.style.SUCCESS(
            f'Total tracks in database: {Track.objects.count()}'
        ))
