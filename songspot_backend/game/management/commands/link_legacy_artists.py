"""
Give the seeded catalogue's artists a Deezer identity.

Around a quarter of the original seeded tracks carry an artist *name* and no
`deezer_artist_id`. That was survivable while artwork lived on the track row.
It is not survivable now: `artists` is keyed on the Deezer ID, so these acts
have no row, no artwork on the select screen, and no entity to pin a directed
session to — they can only be played by name, which is the ambiguity the Artist
model exists to remove.

One call per distinct artist name, once. Roughly three hundred calls against a
budget of six hundred thousand a day.

    python manage.py link_legacy_artists --dry-run
    python manage.py link_legacy_artists
    python manage.py link_legacy_artists --limit 50

**The name has to match.** Deezer's artist search is fuzzy and its ordering is
unusable — `q=weeknd` returns a 2 101-fan namesake above the real one — so a
run that accepted whatever came back first would stamp the wrong identity onto
hundreds of tracks, permanently and invisibly. `catalog.resolve_artist` refuses
any match whose normalised name is not the one asked for, and breaks ties on
follower count. A refused artist keeps working exactly as it does today, by
name.
"""

from django.core.management.base import BaseCommand

from game.models import Track
from game.services import catalog


class Command(BaseCommand):
    help = 'Attach deezer_artist_id to seeded tracks that only have an artist name.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--limit', type=int, default=1000,
            help='Distinct artist names to resolve in this run (default: 1000).',
        )
        parser.add_argument(
            '--dry-run', action='store_true',
            help='Report the matches without writing or resolving.',
        )

    def handle(self, *args, **options):
        names = list(
            Track.objects
            .filter(deezer_artist_id__isnull=True)
            .values_list('artist', flat=True)
            .order_by('artist')
            .distinct()[:options['limit']]
        )
        self.stdout.write(f'{len(names)} artist names without a Deezer identity')

        if options['dry_run']:
            for name in names[:25]:
                self.stdout.write(f'  {name}')
            self.stdout.write(self.style.SUCCESS(f'Dry run: {len(names)} would be resolved.'))
            return

        linked = tracks_linked = refused = 0
        for name in names:
            artist = catalog.resolve_artist(name)
            if artist is None:
                refused += 1
                self.stdout.write(self.style.WARNING(f'  no confident match: {name}'))
                continue

            updated = (
                Track.objects
                .filter(artist=name, deezer_artist_id__isnull=True)
                .update(deezer_artist_id=artist.deezer_id)
            )
            linked += 1
            tracks_linked += updated

        self.stdout.write(self.style.SUCCESS(
            f'Linked {linked} artists ({tracks_linked} tracks). '
            f'{refused} left by name — they keep working as before.'
        ))
