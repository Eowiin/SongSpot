from django.core.management import call_command
from django.core.management.base import BaseCommand
from django.utils import timezone

from game.models import Room, RoomPack, PackTrack
import random

from game.models import DailySong, Track
from game.views import _get_daily_pack_track


class Command(BaseCommand):
    help = 'Pre-generate daily songs and pack daily tracks at a fixed UTC time.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--generate-stems',
            action='store_true',
            help='Generate stems for today\'s pack tracks if missing',
        )

    def handle(self, *args, **options):
        today = timezone.now().date()
        generate_stems = options['generate_stems']

        # Precreate daily songs for all rooms
        for room in Room.objects.all():
            if DailySong.objects.filter(room=room, date=today).exists():
                continue
            used_track_ids = DailySong.objects.filter(room=room).values_list('track_id', flat=True)
            available_tracks = Track.objects.exclude(id__in=used_track_ids)
            if not available_tracks.exists():
                available_tracks = Track.objects.all()
            if not available_tracks.exists():
                continue
            track = random.choice(list(available_tracks))
            DailySong.objects.create(room=room, track=track, date=today)

        # Precreate daily pack tracks and optionally generate stems
        for room_pack in RoomPack.objects.select_related('room', 'pack'):
            daily_track = _get_daily_pack_track(room_pack.room, room_pack.pack, today)
            if not daily_track:
                continue
            if generate_stems:
                pack_track = PackTrack.objects.filter(
                    pack=room_pack.pack,
                    track=daily_track.track
                ).first()
                if pack_track and not all([
                    pack_track.vocals_url,
                    pack_track.drums_url,
                    pack_track.bass_url,
                    pack_track.other_url,
                ]):
                    call_command('generate_pack_stems', pack_track_id=str(pack_track.id))

        self.stdout.write(self.style.SUCCESS('Daily content prepared.'))
