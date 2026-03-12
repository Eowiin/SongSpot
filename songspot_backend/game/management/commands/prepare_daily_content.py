from django.core.management import call_command
from django.core.management.base import BaseCommand
from django.utils import timezone

from game.models import Room, RoomPack, PackTrack

from game.models import DailySong, DAILY_MODE_MIX, DAILY_MODE_GENRE
from game.views import _get_daily_pack_track, _get_or_create_daily_song


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
            for mode in (DAILY_MODE_MIX, DAILY_MODE_GENRE):
                if DailySong.objects.filter(room=room, date=today, mode=mode).exists():
                    continue
                _get_or_create_daily_song(room, today, mode)

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
                track = daily_track.track
                if pack_track and not all([
                    track.vocals_url,
                    track.drums_url,
                    track.bass_url,
                    track.other_url,
                ]):
                    call_command('generate_pack_stems', pack_track_id=str(pack_track.id))

        self.stdout.write(self.style.SUCCESS('Daily content prepared.'))
