"""
WebSocket consumers for real-time features.
"""

import json
import logging
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async
from django.contrib.auth.models import AnonymousUser
from django.db import IntegrityError, transaction

logger = logging.getLogger(__name__)


class RoomChatConsumer(AsyncWebsocketConsumer):
    """
    WebSocket consumer for real-time room chat.

    Connect: ws://host/ws/room/<room_id>/chat/?token=<jwt_token>

    Message format (send):
    {
        "type": "chat_message",
        "message": "Hello everyone!"
    }

    Message format (receive):
    {
        "type": "chat_message",
        "message": "Hello everyone!",
        "user": {
            "id": "uuid",
            "username": "player1",
            "email": "player@example.com"
        },
        "created_at": "2024-01-15T10:00:00Z",
        "id": "message-uuid"
    }
    """

    async def connect(self):
        self.room_id = self.scope['url_route']['kwargs']['room_id']
        self.room_group_name = f'chat_{self.room_id}'
        self.user = self.scope.get('user', AnonymousUser())

        # Reject anonymous users
        if isinstance(self.user, AnonymousUser) or not self.user.is_authenticated:
            logger.warning(
                'WebSocket connect rejected anonymous user room_id=%s path=%s',
                self.room_id,
                self.scope.get('path', ''),
            )
            await self.close(code=4001)  # Unauthorized
            return

        # Check if user is a member of the room
        is_member = await self.is_room_member()
        if not is_member:
            logger.warning(
                'WebSocket connect rejected non-member user_id=%s room_id=%s',
                self.user.id,
                self.room_id,
            )
            await self.close(code=4003)  # Forbidden
            return

        # Join room group
        await self.channel_layer.group_add(
            self.room_group_name,
            self.channel_name
        )

        await self.accept()
        logger.info(
            'WebSocket connect accepted user_id=%s room_id=%s',
            self.user.id,
            self.room_id,
        )

        # Send join notification to room
        await self.channel_layer.group_send(
            self.room_group_name,
            {
                'type': 'user_joined',
                'user': self.serialize_user(self.user),
            }
        )

    async def disconnect(self, close_code):
        # Leave room group
        if hasattr(self, 'room_group_name'):
            # Send leave notification
            if hasattr(self, 'user') and self.user.is_authenticated:
                await self.channel_layer.group_send(
                    self.room_group_name,
                    {
                        'type': 'user_left',
                        'user': self.serialize_user(self.user),
                    }
                )

            await self.channel_layer.group_discard(
                self.room_group_name,
                self.channel_name
            )

    async def receive(self, text_data):
        """Handle incoming WebSocket messages."""
        try:
            data = json.loads(text_data)
            message_type = data.get('type', 'chat_message')

            if message_type == 'chat_message':
                await self.handle_chat_message(data)
            elif message_type == 'typing':
                await self.handle_typing(data)
        except json.JSONDecodeError:
            await self.send(text_data=json.dumps({
                'type': 'error',
                'message': 'Invalid JSON format'
            }))

    async def handle_chat_message(self, data):
        """Process and broadcast a chat message."""
        message_text = data.get('message', '').strip()
        client_message_id = str(data.get('client_message_id', '')).strip() or None

        if not message_text:
            await self.send(text_data=json.dumps({
                'type': 'error',
                'message': 'Message cannot be empty'
            }))
            return

        if len(message_text) > 500:
            await self.send(text_data=json.dumps({
                'type': 'error',
                'message': 'Message too long (max 500 characters)'
            }))
            return

        if client_message_id is not None and len(client_message_id) > 64:
            await self.send(text_data=json.dumps({
                'type': 'error',
                'message': 'Client message ID too long (max 64 characters)'
            }))
            return

        # Save message to database
        saved_message = await self.save_message(message_text, client_message_id)

        if not saved_message:
            await self.send(text_data=json.dumps({
                'type': 'error',
                'message': 'Unable to save message'
            }))

    async def handle_typing(self, data):
        """Broadcast typing indicator."""
        is_typing = data.get('is_typing', False)

        await self.channel_layer.group_send(
            self.room_group_name,
            {
                'type': 'typing_indicator',
                'user': self.serialize_user(self.user),
                'is_typing': is_typing,
            }
        )

    # Event handlers for group messages

    async def chat_message(self, event):
        """Send chat message to WebSocket."""
        await self.send(text_data=json.dumps({
            'type': 'chat_message',
            'id': event['id'],
            'message': event['message'],
            'client_message_id': event.get('client_message_id'),
            'user': event['user'],
            'created_at': event['created_at'],
        }))

    async def user_joined(self, event):
        """Send user joined notification."""
        await self.send(text_data=json.dumps({
            'type': 'user_joined',
            'user': event['user'],
        }))

    async def user_left(self, event):
        """Send user left notification."""
        await self.send(text_data=json.dumps({
            'type': 'user_left',
            'user': event['user'],
        }))

    async def typing_indicator(self, event):
        """Send typing indicator (don't send to the typer)."""
        if event['user']['id'] != str(self.user.id):
            await self.send(text_data=json.dumps({
                'type': 'typing',
                'user': event['user'],
                'is_typing': event['is_typing'],
            }))

    async def stems_ready(self, event):
        """Notify clients that stems have finished generating for a pack track."""
        await self.send(text_data=json.dumps({
            'type': 'stems_ready',
            'pack_id': event['pack_id'],
            'pack_track_id': event['pack_track_id'],
        }))

    async def leaderboard_updated(self, event):
        """Notify clients that the room leaderboard changed."""
        await self.send(text_data=json.dumps({
            'type': 'leaderboard_updated',
            'room_id': event.get('room_id'),
            'user_id': event.get('user_id'),
        }))

    # Database operations

    @database_sync_to_async
    def is_room_member(self):
        """Check if the user is a member of the room."""
        from .models import Room, RoomUser

        try:
            room = Room.objects.get(id=self.room_id)
            return RoomUser.objects.filter(room=room, user=self.user).exists()
        except Room.DoesNotExist:
            return False

    @database_sync_to_async
    def save_message(self, message_text, client_message_id=None):
        """Save message to database."""
        from .models import Room, RoomMessage

        try:
            room = Room.objects.get(id=self.room_id)
            if client_message_id:
                lookup = {
                    'room': room,
                    'user': self.user,
                    'client_message_id': client_message_id,
                }
                try:
                    with transaction.atomic():
                        message, _ = RoomMessage.objects.get_or_create(
                            **lookup,
                            defaults={'message': message_text},
                        )
                except IntegrityError:
                    message = RoomMessage.objects.get(**lookup)
            else:
                message = RoomMessage.objects.create(
                    room=room,
                    user=self.user,
                    message=message_text
                )
            return message
        except Room.DoesNotExist:
            return None

    def serialize_user(self, user):
        """Serialize user for JSON response."""
        return {
            'id': str(user.id),
            'username': user.username,
            'email': user.email,
        }
