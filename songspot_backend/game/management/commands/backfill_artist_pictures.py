"""
Fill in missing artist artwork on the `artists` table.

Rewritten for migration 0016, which moved artwork off `tracks`. The previous
version searched Deezer *by name* — two calls per artist, and the exact
ambiguity the Artist entity was introduced to remove: `search/artist?q=weeknd`
returns a 2 101-fan namesake above the real one, so a run could quietly attach
the wrong face to a chart act.

This looks artists up by their Deezer ID instead: one call, no ambiguity.

Mostly unnecessary now. `catalog.sync_artists_from_tracks` records artwork as
tracks are imported, and `crawl_artists` fills it in as it walks. This is for
rows that predate both, or whose picture came back empty at the time.

    python manage.py backfill_artist_pictures
    python manage.py backfill_artist_pictures --limit 500
    python manage.py backfill_artist_pictures --dry-run
"""

from django.core.management.base import BaseCommand
from django.db.models import Q

from game.models import Artist
from game.services import DeezerService
from game.services.deezer_http import BULK_MAX_WAIT, DeezerHttp


class Command(BaseCommand):
    help = 'Fetch missing picture_url for artists, by Deezer ID.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--limit', type=int, default=1000,
            help='Artists to process in this run (default: 1000).',
        )
        parser.add_argument(
            '--dry-run', action='store_true',
            help='Report what is missing without calling Deezer or writing.',
        )

    def handle(self, *args, **options):
        missing = (
            Artist.objects
            .filter(Q(picture_url__isnull=True) | Q(picture_url=''), is_blocked=False)
            .order_by('-nb_fan')[:options['limit']]
        )
        total = len(missing)
        self.stdout.write(f'{total} artists without artwork')

        if options['dry_run']:
            for artist in missing[:20]:
                self.stdout.write(f'  {artist.name} ({artist.deezer_id})')
            self.stdout.write(self.style.SUCCESS(f'Dry run: {total} would be fetched.'))
            return

        # Nobody is waiting on this, so it queues behind the rate limiter
        # rather than giving up the way a web request does.
        deezer = DeezerService(http=DeezerHttp(max_wait=BULK_MAX_WAIT))
        updated = 0

        for artist in missing:
            payload = deezer.get_artist(artist.deezer_id) or {}
            picture = (
                payload.get('picture_xl') or payload.get('picture_big') or
                payload.get('picture_medium') or payload.get('picture_small') or
                payload.get('picture')
            )
            if not picture:
                continue
            artist.picture_url = picture
            # nb_fan comes free with this payload and is what artist search
            # ranks on, so take it while we are here.
            if payload.get('nb_fan'):
                artist.nb_fan = payload['nb_fan']
            artist.save(update_fields=['picture_url', 'nb_fan'])
            updated += 1

        self.stdout.write(self.style.SUCCESS(f'Updated {updated} of {total}.'))
