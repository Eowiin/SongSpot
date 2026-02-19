from celery import shared_task

from authentication.services.push_service import send_push_to_users


@shared_task
def notify_daily_song_available_task(daily_song_id: str):
    from game.models import DailySong, RoomUser

    daily_song = DailySong.objects.select_related('room').filter(id=daily_song_id).first()
    if not daily_song:
        return {'success_count': 0, 'failure_count': 0, 'skipped': True}

    user_ids = list(
        RoomUser.objects.filter(room=daily_song.room).values_list('user_id', flat=True)
    )
    if not user_ids:
        return {'success_count': 0, 'failure_count': 0, 'skipped': True}

    room_label = daily_song.room.name or daily_song.room.room_code
    return send_push_to_users(
        [str(user_id) for user_id in user_ids],
        title='New daily song is live',
        body=f"Today's song is now available in {room_label}.",
        data={
            'type': 'daily_song_available',
            'room_id': str(daily_song.room_id),
            'daily_song_id': str(daily_song.id),
            'date': str(daily_song.date),
        },
        notification_type='daily_song',
    )


@shared_task
def notify_room_message_task(message_id: str):
    from game.models import RoomMessage, RoomUser

    message = RoomMessage.objects.select_related('room', 'user').filter(id=message_id).first()
    if not message:
        return {'success_count': 0, 'failure_count': 0, 'skipped': True}

    recipient_ids = list(
        RoomUser.objects.filter(room=message.room)
        .exclude(user=message.user)
        .values_list('user_id', flat=True)
    )
    if not recipient_ids:
        return {'success_count': 0, 'failure_count': 0, 'skipped': True}

    room_label = message.room.name or message.room.room_code
    preview = message.message.strip()
    if len(preview) > 90:
        preview = f'{preview[:87]}...'

    return send_push_to_users(
        [str(user_id) for user_id in recipient_ids],
        title=f'New message in {room_label}',
        body=f'{message.user.username}: {preview}',
        data={
            'type': 'room_message',
            'room_id': str(message.room_id),
            'message_id': str(message.id),
            'sender_user_id': str(message.user_id),
        },
        notification_type='message',
    )
