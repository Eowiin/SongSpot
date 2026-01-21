"""
WebSocket URL routing for the game app.
"""

from django.urls import re_path
from . import consumers

websocket_urlpatterns = [
    re_path(r'ws/room/(?P<room_id>[0-9a-f-]+)/chat/$', consumers.RoomChatConsumer.as_asgi()),
]
