import json
import time
from pathlib import Path

from django.core.management.base import BaseCommand

from game.services import DeezerService
from ._artist_utils import fetch_and_save_artist, resolve_artist_id

CURATED_FILE = Path(__file__).resolve().parent.parent / 'curated_artists.json'


class Command(BaseCommand):
    help = 'Seed tracks from the curated artist list (game/management/curated_artists.json)'

    def add_arguments(self, parser):
        parser.add_argument(
            '--tracks',
            type=int,
            default=10,
            help='Number of top tracks to fetch per artist (default: 10)',
        )
        parser.add_argument(
            '--delay',
            type=float,
            default=0.2,
            help='Seconds between Deezer requests (default: 0.2)',
        )
        parser.add_argument(
            '--skip-existing',
            action='store_true',
            default=True,
            help='Skip artists that already have tracks in the DB (default: true)',
        )
        parser.add_argument(
            '--force',
            action='store_true',
            default=False,
            help='Re-fetch all artists even if they already have tracks',
        )

    def handle(self, *args, **options):
        tracks_per_artist = options['tracks']
        delay = options['delay']
        skip_existing = not options['force']

        artist_names = json.loads(CURATED_FILE.read_text())
        deezer = DeezerService()

        total = len(artist_names)
        self.stdout.write(self.style.WARNING(
            f'Seeding {total} artists — {tracks_per_artist} tracks each'
        ))

        from game.models import Track

        totals = {'added': 0, 'updated': 0, 'skipped': 0, 'not_found': 0}

        for i, name in enumerate(artist_names, 1):
            if skip_existing and Track.objects.filter(artist__iexact=name).exists():
                self.stdout.write(f'[{i}/{total}] — {name} (already in DB, skipping)')
                continue

            self.stdout.write(f'[{i}/{total}] {name}')

            artist_id = resolve_artist_id(deezer, name)
            if not artist_id:
                self.stdout.write(self.style.ERROR(f'  Not found on Deezer'))
                totals['not_found'] += 1
                time.sleep(delay)
                continue

            counts = fetch_and_save_artist(
                deezer, artist_id, name, tracks_per_artist, self.stdout, delay=delay,
            )
            for key in ('added', 'updated', 'skipped'):
                totals[key] += counts[key]

            self.stdout.write(self.style.SUCCESS(
                f'  ✓ +{counts["added"]} added, {counts["updated"]} updated, {counts["skipped"]} skipped'
            ))

        self.stdout.write(self.style.SUCCESS(
            f'\nDone. {totals["added"]} tracks added, {totals["updated"]} updated, '
            f'{totals["skipped"]} skipped, {totals["not_found"]} artists not found on Deezer.'
        ))
