"""
Record track lengths so album filler stops being played.

`Track.duration` arrived after most of the catalogue was imported, and without
it `matching.is_non_song` cannot recognise a 30-second voice note. New imports
and refreshes fill it in on their own; this command catches up the rows that
players can reach today.

Two passes:

1. **Titles** (database only, no Deezer call): flags tracks whose title already
   says they are skits, whatever their length.
2. **Albums**: walks the discography of the most-followed artists that still
   have tracks of unknown length. One call lists an artist's albums and one call
   per album lists its tracks, durations included, through the same import path
   as directed play — so it only ever fills gaps.

    python manage.py backfill_track_durations                    # a night's budget
    python manage.py backfill_track_durations --max-calls 500
    python manage.py backfill_track_durations --artist-id 113915572   # one artist
    python manage.py backfill_track_durations --titles-only

Queues behind the shared Deezer rate limiter like the other crawls, so it never
takes calls away from players. Resumable: an artist walked in the last 30 days
is skipped, so a run that stops halfway continues where it left off.
"""

from argparse import ArgumentParser
from typing import Any

from django.core.management.base import BaseCommand

from game.models import Artist, Track
from game.services import DeezerService
from game.services.cache_utils import cache_get, cache_set
from game.services.catalog import _import_artist_albums
from game.services.deezer_http import BULK_MAX_WAIT, DeezerHttp
from game.services.matching import is_non_song

# get_artist_albums lists at most 25 albums, plus the listing call itself.
CALLS_PER_ARTIST = 26
WALKED_TTL = 30 * 24 * 3600
BATCH = 500


def _walked_key(artist_id: int) -> str:
    return f'duration_backfill:artist:{artist_id}'


class Command(BaseCommand):
    help = 'Fill in Track.duration and flag album filler (voice notes, skits).'

    def add_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            '--max-calls', type=int, default=20_000,
            help='Deezer call budget for the album pass (default 20000).',
        )
        parser.add_argument(
            '--artist-id', type=int,
            help='Walk only this Deezer artist, even if walked recently.',
        )
        parser.add_argument(
            '--titles-only', action='store_true',
            help='Run the database-only title pass and stop.',
        )

    def handle(self, *args: Any, **options: Any) -> None:
        flagged = self._flag_titles()
        self.stdout.write(f'title pass: {flagged} tracks flagged as filler')
        if options['titles_only']:
            return

        deezer = DeezerService(http=DeezerHttp(max_wait=BULK_MAX_WAIT))
        if options['artist_id']:
            artist_ids = [options['artist_id']]
        else:
            artist_ids = self._artists_to_walk(max(1, options['max_calls']) // CALLS_PER_ARTIST)

        for done, artist_id in enumerate(artist_ids, start=1):
            artist = Artist.objects.filter(deezer_id=artist_id).first()
            picture = artist.picture_url if artist else None
            # `wanted` set out of reach so the walk covers every listed album
            # instead of stopping once a session's worth of tracks exists.
            _import_artist_albums(deezer, artist_id, picture, wanted=10**9, already=[])
            cache_set(_walked_key(artist_id), True, WALKED_TTL)
            unknown = Track.objects.filter(deezer_artist_id=artist_id, duration__isnull=True).count()
            filler = Track.objects.filter(deezer_artist_id=artist_id, is_non_song=True).count()
            name = artist.name if artist else artist_id
            self.stdout.write(
                f'[{done}/{len(artist_ids)}] {name}: {filler} filler, {unknown} still unknown'
            )

    def _flag_titles(self) -> int:
        """Flag skits by title; the only filler recognisable without a length."""
        updates: list[Track] = []
        rows = Track.objects.filter(title__icontains='skit', is_non_song=False).only(
            'id', 'title', 'duration', 'is_non_song',
        )
        for track in rows.iterator(chunk_size=BATCH):
            if is_non_song(track.title, track.duration):
                track.is_non_song = True
                updates.append(track)
        Track.objects.bulk_update(updates, ['is_non_song'], batch_size=BATCH)
        return len(updates)

    def _artists_to_walk(self, limit: int) -> list[int]:
        """Most-followed artists first: they are the ones players pick."""
        pending = (
            Artist.objects
            .filter(is_blocked=False)
            .filter(
                deezer_id__in=Track.objects
                .filter(duration__isnull=True, has_preview=True)
                .values('deezer_artist_id')
            )
            .order_by('-nb_fan')
            .values_list('deezer_id', flat=True)
        )
        chosen: list[int] = []
        for artist_id in pending.iterator(chunk_size=BATCH):
            if cache_get(_walked_key(artist_id)):
                continue
            chosen.append(artist_id)
            if len(chosen) >= limit:
                break
        return chosen
