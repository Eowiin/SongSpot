import json
from pathlib import Path

from django.core.management.base import BaseCommand, CommandError

from game.services import DeezerService
from ._artist_utils import fetch_and_save_artist, resolve_artist_id

CURATED_FILE = Path(__file__).resolve().parent.parent / 'curated_artists.json'


class Command(BaseCommand):
    help = 'Add a single artist by name: fetch their top tracks and optionally save to curated list'

    def add_arguments(self, parser):
        parser.add_argument(
            'name',
            type=str,
            help='Artist name to search on Deezer',
        )
        parser.add_argument(
            '--tracks',
            type=int,
            default=10,
            help='Number of top tracks to fetch (default: 10)',
        )
        parser.add_argument(
            '--delay',
            type=float,
            default=0.2,
            help='Seconds between Deezer requests (default: 0.2)',
        )
        parser.add_argument(
            '--save-to-list',
            action='store_true',
            default=False,
            help='Also append the artist to curated_artists.json',
        )

    def handle(self, *args, **options):
        name = options['name'].strip()
        tracks_per_artist = options['tracks']
        delay = options['delay']
        save_to_list = options['save_to_list']

        deezer = DeezerService()

        self.stdout.write(f'Searching Deezer for "{name}"...')
        artist = deezer.search_artist(name)
        if not artist:
            raise CommandError(f'Artist "{name}" not found on Deezer.')

        artist_id = artist['id']
        found_name = artist.get('name', name)
        self.stdout.write(self.style.SUCCESS(f'Found: {found_name} (id={artist_id})'))

        counts = fetch_and_save_artist(
            deezer, artist_id, found_name, tracks_per_artist, self.stdout, delay=delay,
        )

        self.stdout.write(self.style.SUCCESS(
            f'\nDone. {counts["added"]} tracks added, '
            f'{counts["updated"]} updated, {counts["skipped"]} skipped.'
        ))

        if save_to_list:
            curated = json.loads(CURATED_FILE.read_text())
            if found_name not in curated:
                curated.append(found_name)
                CURATED_FILE.write_text(json.dumps(curated, indent=2, ensure_ascii=False))
                self.stdout.write(self.style.SUCCESS(f'Added "{found_name}" to curated_artists.json'))
            else:
                self.stdout.write(f'"{found_name}" is already in curated_artists.json')
