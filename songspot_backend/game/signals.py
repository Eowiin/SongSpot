import logging

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.db.models.signals import post_save
from django.dispatch import receiver

from authentication.tasks import notify_daily_song_available_task, notify_room_message_task
from .models import DailySong, RoomMessage

logger = logging.getLogger(__name__)


def _dispatch_or_fallback(task, arg):
    try:
        task.delay(arg)
    except Exception:
        task(arg)


def _broadcast_room_message(instance: RoomMessage) -> None:
    """
    Broadcast newly created room messages over WebSocket so REST-created
    messages and WebSocket-created messages follow the same realtime path.
    """
    channel_layer = get_channel_layer()
    if channel_layer is None:
        return

    try:
        async_to_sync(channel_layer.group_send)(
            f'chat_{instance.room_id}',
            {
                'type': 'chat_message',
                'id': str(instance.id),
                'message': instance.message,
                'user': {
                    'id': str(instance.user_id),
                    'username': instance.user.username,
                    'email': instance.user.email,
                },
                'created_at': instance.created_at.isoformat(),
            },
        )
    except Exception:
        logger.exception('Failed to broadcast room message over channel layer.')


@receiver(post_save, sender=DailySong)
def on_daily_song_created(sender, instance, created, **kwargs):
    if created:
        _dispatch_or_fallback(notify_daily_song_available_task, str(instance.id))


@receiver(post_save, sender=RoomMessage)
def on_room_message_created(sender, instance, created, **kwargs):
    if created:
        _dispatch_or_fallback(notify_room_message_task, str(instance.id))
        _broadcast_room_message(instance)
