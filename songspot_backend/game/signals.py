from django.db.models.signals import post_save
from django.dispatch import receiver

from authentication.tasks import notify_daily_song_available_task, notify_room_message_task
from .models import DailySong, RoomMessage


def _dispatch_or_fallback(task, arg):
    try:
        task.delay(arg)
    except Exception:
        task(arg)


@receiver(post_save, sender=DailySong)
def on_daily_song_created(sender, instance, created, **kwargs):
    if created:
        _dispatch_or_fallback(notify_daily_song_available_task, str(instance.id))


@receiver(post_save, sender=RoomMessage)
def on_room_message_created(sender, instance, created, **kwargs):
    if created:
        _dispatch_or_fallback(notify_room_message_task, str(instance.id))
