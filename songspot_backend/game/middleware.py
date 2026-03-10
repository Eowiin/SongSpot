"""
WebSocket authentication middleware using JWT tokens.
"""

import logging

from channels.db import database_sync_to_async
from channels.middleware import BaseMiddleware
from django.contrib.auth.models import AnonymousUser
from rest_framework_simplejwt.tokens import AccessToken
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError
from urllib.parse import parse_qs

logger = logging.getLogger(__name__)


def _header_value(scope, name):
    target = name.lower().encode()
    for key, value in scope.get('headers', []):
        if key == target:
            return value.decode(errors='ignore')
    return None


@database_sync_to_async
def get_user_from_token(token_key):
    """
    Validate JWT token and return the associated user.
    """
    from django.contrib.auth import get_user_model
    User = get_user_model()

    try:
        access_token = AccessToken(token_key)
        user_id = access_token['user_id']
        return User.objects.get(id=user_id)
    except (InvalidToken, TokenError, User.DoesNotExist):
        return AnonymousUser()


class JWTAuthMiddleware(BaseMiddleware):
    """
    Custom middleware that authenticates WebSocket connections using JWT tokens.

    The token can be passed either:
    1. As a query parameter: ws://host/ws/room/123/chat/?token=<jwt_token>
    2. In the subprotocol header (for clients that support it)

    Usage in Flutter:
        WebSocketChannel.connect(
            Uri.parse('ws://host/ws/room/$roomId/chat/?token=$accessToken'),
        )
    """

    async def __call__(self, scope, receive, send):
        path = scope.get('path', '')
        host = _header_value(scope, 'host')
        origin = _header_value(scope, 'origin')

        # Try to get token from query string
        query_string = scope.get('query_string', b'').decode()
        query_params = parse_qs(query_string)
        token = query_params.get('token', [None])[0]

        # If no token in query string, try subprotocols
        if not token:
            subprotocols = scope.get('subprotocols', [])
            for protocol in subprotocols:
                if protocol.startswith('bearer.'):
                    token = protocol[7:]  # Remove 'bearer.' prefix
                    break

        if token:
            scope['user'] = await get_user_from_token(token)
            if isinstance(scope['user'], AnonymousUser):
                logger.warning(
                    'WebSocket auth rejected token path=%s host=%s origin=%s',
                    path,
                    host,
                    origin,
                )
            else:
                logger.info(
                    'WebSocket auth accepted user_id=%s path=%s host=%s origin=%s',
                    scope['user'].id,
                    path,
                    host,
                    origin,
                )
        else:
            scope['user'] = AnonymousUser()
            logger.warning(
                'WebSocket auth missing token path=%s host=%s origin=%s',
                path,
                host,
                origin,
            )

        return await super().__call__(scope, receive, send)
