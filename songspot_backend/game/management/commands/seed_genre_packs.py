import random
import re

from django.core.management.base import BaseCommand

from game.models import SongPack, Track, PackTrack
from game.services import DeezerService


GENRE_MAP = {
    'pop': 132,
    'rock': 152,
    'hiphop': 116,
    'rap': 116,
}


class Command(BaseCommand):
    help = 'Fetch genre tracks from Deezer and create packs with ordered tracks.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--count-per-pack',
            type=int,
            default=30,
            help='Tracks per pack (default: 30)',
        )
        parser.add_argument(
            '--genres',
            type=str,
            default='pop,rock,hiphop',
            help='Comma-separated genres (pop, rock, hiphop)',
        )
        parser.add_argument(
            '--max-per-artist',
            type=int,
            default=1,
            help='Maximum tracks per artist in a pack (default: 1)',
        )
        parser.add_argument(
            '--artist-pool',
            type=int,
            default=200,
            help='How many genre artists to sample (default: 200)',
        )
        parser.add_argument(
            '--tracks-per-artist-fetch',
            type=int,
            default=10,
            help='Top tracks fetched per artist (default: 10)',
        )

    def handle(self, *args, **options):
        count_per_pack = options['count_per_pack']
        genres = [g.strip().lower() for g in options['genres'].split(',') if g.strip()]
        max_per_artist = options['max_per_artist']
        artist_pool = options['artist_pool']
        tracks_per_artist_fetch = options['tracks_per_artist_fetch']

        deezer = DeezerService()

        for genre in genres:
            genre_id = GENRE_MAP.get(genre)
            if not genre_id:
                self.stdout.write(self.style.WARNING(f'Skipping unknown genre: {genre}'))
                continue

            base_name = f'{genre.capitalize()} Pack'
            existing_packs = SongPack.objects.filter(name__istartswith=base_name)
            used_track_ids = set(
                PackTrack.objects.filter(pack__in=existing_packs)
                .values_list('track_id', flat=True)
            )

            self.stdout.write(self.style.WARNING(f'Fetching {count_per_pack} {genre} tracks...'))
            artists = deezer.get_genre_artists(genre_id, limit=artist_pool)
            if not artists:
                self.stdout.write(self.style.WARNING(f'No artists found for {genre}.'))
                continue
            random.shuffle(artists)

            selected_tracks = []
            selected_track_ids = set()
            artist_counts = {}
            for artist in artists:
                if len(selected_tracks) >= count_per_pack:
                    break
                artist_id = artist.get('id')
                if not artist_id:
                    continue
                top_tracks = deezer.get_artist_top_tracks(artist_id, limit=tracks_per_artist_fetch)
                for track_data in top_tracks:
                    if len(selected_tracks) >= count_per_pack:
                        break
                    track_info = deezer.extract_track_info(track_data)
                    if not track_info['preview_url']:
                        continue
                    artist_name = track_info['artist']
                    if artist_counts.get(artist_name, 0) >= max_per_artist:
                        continue

                    track, _ = Track.objects.get_or_create(
                        title=track_info['title'],
                        artist=track_info['artist'],
                        defaults={
                            'preview_url': track_info['preview_url'],
                            'cover_url': track_info.get('cover_url'),
                            'deezer_id': track_info.get('deezer_id'),
                        },
                    )

                    if track.id in used_track_ids:
                        continue

                    if track.id in selected_track_ids:
                        continue

                    selected_tracks.append(track)
                    selected_track_ids.add(track.id)
                    artist_counts[artist_name] = artist_counts.get(artist_name, 0) + 1

            if len(selected_tracks) < count_per_pack:
                self.stdout.write(self.style.WARNING(
                    f'Not enough unique {genre} tracks to create a new pack ({len(selected_tracks)}/{count_per_pack}).'
                ))
                continue

            pack_name = self._next_pack_name(base_name, existing_packs.values_list('name', flat=True))
            pack = SongPack.objects.create(
                name=pack_name,
                description=f'{genre.capitalize()} focused stem pack',
                price_coins=600,
                is_featured=True,
            )

            order = 1
            for track in selected_tracks:
                PackTrack.objects.create(
                    pack=pack,
                    track=track,
                    order_in_pack=order,
                )
                order += 1

            self.stdout.write(self.style.SUCCESS(
                f'Pack "{pack_name}" ready with {len(selected_tracks)} tracks.'
            ))

    def _next_pack_name(self, base_name, existing_names):
        max_suffix = 1 if base_name in existing_names else 0
        pattern = re.compile(rf'^{re.escape(base_name)}\s+(\d+)$', re.IGNORECASE)
        for name in existing_names:
            match = pattern.match(name)
            if match:
                max_suffix = max(max_suffix, int(match.group(1)))
        if max_suffix == 0:
            return base_name
        return f'{base_name} {max_suffix + 1}'
