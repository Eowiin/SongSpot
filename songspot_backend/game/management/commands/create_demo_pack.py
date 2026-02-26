"""
Create a Demo Pack: a free pack (0 coins) that is NOT auto-unlocked on room
creation. Users must explicitly go to the packs list and "buy" it for 0 coins
to unlock it. This gives new users a chance to try the game before spending coins.

The demo pack is seeded with the highest-ranked Pop tracks available.

Usage:
    python manage.py create_demo_pack
    python manage.py create_demo_pack --track-count 10 --min-rank 900000
"""

from django.core.management.base import BaseCommand

from game.models import SongPack, Track, PackTrack
from game.services import DeezerService


DEMO_POP_GENRE_ID = 132
DEFAULT_TRACK_COUNT = 10
DEFAULT_MIN_RANK = 800_000


class Command(BaseCommand):
    help = 'Create a free demo pack (0 coins, not auto-unlocked) with top-ranked pop songs.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--track-count',
            type=int,
            default=DEFAULT_TRACK_COUNT,
            help=f'Number of tracks in the demo pack (default: {DEFAULT_TRACK_COUNT})',
        )
        parser.add_argument(
            '--min-rank',
            type=int,
            default=DEFAULT_MIN_RANK,
            help=f'Minimum Deezer rank (default: {DEFAULT_MIN_RANK})',
        )
        parser.add_argument(
            '--force',
            action='store_true',
            help='Create a new demo pack even if one already exists',
        )

    def handle(self, *args, **options):
        if not options['force'] and SongPack.objects.filter(name='Demo Pack').exists():
            self.stdout.write(self.style.WARNING(
                'A Demo Pack already exists. Use --force to create another.'
            ))
            return

        deezer = DeezerService()
        track_count = options['track_count']
        min_rank = options['min_rank']

        self.stdout.write('Fetching top-ranked pop tracks...')
        raw_tracks = deezer.get_genre_chart_tracks(DEMO_POP_GENRE_ID, limit=100)

        candidates = []
        seen_deezer_ids = set()
        for raw in raw_tracks:
            info = deezer.extract_track_info(raw)
            if not info['preview_url']:
                continue
            deezer_id = info.get('deezer_id')
            if deezer_id in seen_deezer_ids:
                continue
            seen_deezer_ids.add(deezer_id)
            candidates.append(info)

        candidates.sort(key=lambda t: t.get('rank', 0), reverse=True)
        filtered = [t for t in candidates if t.get('rank', 0) >= min_rank]
        if len(filtered) < track_count:
            self.stdout.write(self.style.WARNING(
                f'Only {len(filtered)} tracks above rank {min_rank}. '
                f'Using top {min(track_count, len(candidates))} available.'
            ))
            filtered = candidates

        selected = []
        seen_artists = set()
        for info in filtered:
            if len(selected) >= track_count:
                break
            if info['artist'] in seen_artists:
                continue
            track, _ = Track.objects.get_or_create(
                title=info['title'],
                artist=info['artist'],
                defaults={
                    'preview_url': info['preview_url'],
                    'cover_url': info.get('cover_url'),
                    'deezer_id': info.get('deezer_id'),
                    'release_year': info.get('release_year'),
                    'genre': 'Pop',
                },
            )
            selected.append(track)
            seen_artists.add(info['artist'])

        if not selected:
            self.stdout.write(self.style.ERROR('No tracks found — aborting.'))
            return

        pack = SongPack.objects.create(
            name='Demo Pack',
            description='Try the stem guessing game for free with iconic songs.',
            category='pop',
            price_coins=0,
            is_free=True,
            auto_unlock=False,
            is_featured=True,
        )
        for order, track in enumerate(selected, start=1):
            PackTrack.objects.create(pack=pack, track=track, order_in_pack=order)

        self.stdout.write(self.style.SUCCESS(
            f'Created "Demo Pack" with {len(selected)} tracks. '
            f'(free, not auto-unlocked — users must buy it at 0 coins)'
        ))
