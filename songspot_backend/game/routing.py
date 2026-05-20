from django.urls import path
from . import consumers

websocket_urlpatterns = [
    path('ws/duel/queue/', consumers.MatchmakingConsumer.as_asgi()),
    path('ws/duel/<uuid:match_id>/', consumers.DuelConsumer.as_asgi()),
]
