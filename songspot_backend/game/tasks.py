from celery import shared_task
from django.core.management import call_command
from django.utils import timezone

from .models import PackBundleStemJob, PackTrack, RoomPack


def _notify_stems_ready(pack_track):
    """Send a WebSocket event to all rooms that own this pack."""
    try:
        from channels.layers import get_channel_layer
        from asgiref.sync import async_to_sync

        channel_layer = get_channel_layer()
        if channel_layer is None:
            return

        pack_id = str(pack_track.pack_id)
        room_ids = list(
            RoomPack.objects.filter(pack_id=pack_track.pack_id)
            .values_list('room_id', flat=True)
        )

        for room_id in room_ids:
            async_to_sync(channel_layer.group_send)(
                f'chat_{room_id}',
                {
                    'type': 'stems_ready',
                    'pack_id': pack_id,
                    'pack_track_id': str(pack_track.id),
                },
            )
    except Exception:
        pass


@shared_task(bind=True)
def generate_pack_stems_task(self, pack_track_id: str):
    pack_track = PackTrack.objects.filter(id=pack_track_id).first()
    if not pack_track:
        return

    job, _ = PackBundleStemJob.objects.get_or_create(pack_track=pack_track)
    job.status = PackBundleStemJob.STATUS_RUNNING
    job.started_at = timezone.now()
    job.error_message = ''
    job.save(update_fields=['status', 'started_at', 'error_message'])

    try:
        call_command('generate_pack_stems', pack_track_id=pack_track_id)
        job.status = PackBundleStemJob.STATUS_READY
        job.completed_at = timezone.now()
        job.save(update_fields=['status', 'completed_at'])
        _notify_stems_ready(pack_track)
    except Exception as exc:
        job.status = PackBundleStemJob.STATUS_FAILED
        job.error_message = str(exc)
        job.completed_at = timezone.now()
        job.save(update_fields=['status', 'error_message', 'completed_at'])
        raise
