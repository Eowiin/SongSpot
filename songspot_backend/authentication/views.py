from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.token_blacklist.models import OutstandingToken
from rest_framework_simplejwt.exceptions import TokenError
from django.contrib.auth import authenticate, get_user_model
from django.db import transaction
from django.utils import timezone
from django.http import HttpResponse
import json
from .models import UserDevicePushToken, CoinTransaction
from .serializers import (
    UserRegistrationSerializer,
    UserSerializer,
    UserProfileSerializer,
    LoginSerializer,
    PushDeviceRegisterSerializer,
    PushDeviceUnregisterSerializer,
    ChangeEmailSerializer,
    ChangePasswordSerializer,
    DeleteAccountSerializer,
)
from songspot.throttling import AuthRateThrottle

User = get_user_model()

class RegisterView(APIView):
    """
    Register a new user account.

    POST /api/auth/register/
    Body: {
        "email": "user@example.com",
        "username": "username",
        "password": "password123",
        "password_confirm": "password123"
    }

    Returns:
    - user: user details
    - tokens: access and refresh tokens

    Rate limited: 5 requests per minute
    """
    permission_classes = [AllowAny]
    throttle_classes = [AuthRateThrottle]

    def post(self, request):
        serializer = UserRegistrationSerializer(data=request.data)
        if serializer.is_valid():
            user = serializer.save()
            refresh = RefreshToken.for_user(user)

            return Response({
                'user': UserSerializer(user).data,
                'tokens': {
                    'refresh': str(refresh),
                    'access': str(refresh.access_token),
                },
                'message': 'User registered successfully'
            }, status=status.HTTP_201_CREATED)

        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class LoginView(APIView):
    """
    Login with email and password.

    POST /api/auth/login/
    Body: {
        "email": "user@example.com",
        "password": "password123"
    }

    Returns:
    - user: user details
    - tokens: access token (valid 1 hour) and refresh token (valid 90 days)

    Note: Store both tokens securely on the mobile device.
    Use access token for API calls. When it expires, use refresh token to get new tokens.

    Rate limited: 5 requests per minute (prevents brute force)
    """
    permission_classes = [AllowAny]
    throttle_classes = [AuthRateThrottle]

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        email = serializer.validated_data['email']
        password = serializer.validated_data['password']

        user = authenticate(request, email=email, password=password)

        if user is not None:
            refresh = RefreshToken.for_user(user)

            return Response({
                'user': UserSerializer(user).data,
                'tokens': {
                    'refresh': str(refresh),
                    'access': str(refresh.access_token),
                },
                'message': 'Login successful'
            }, status=status.HTTP_200_OK)

        return Response({
            'error': 'Invalid credentials'
        }, status=status.HTTP_401_UNAUTHORIZED)


class RefreshTokenView(APIView):
    """
    Refresh the access token using a refresh token.

    POST /api/auth/token/refresh/
    Body: {
        "refresh": "your_refresh_token_here"
    }

    Returns:
    - access: new access token
    - refresh: new refresh token (rotated for security)

    Note: The old refresh token is automatically blacklisted for security.
    Store the new tokens and use them for subsequent requests.
    """
    permission_classes = [AllowAny]

    def post(self, request):
        refresh_token = request.data.get('refresh')

        if not refresh_token:
            return Response({
                'error': 'Refresh token is required'
            }, status=status.HTTP_400_BAD_REQUEST)

        try:
            refresh = RefreshToken(refresh_token)

            data = {
                'access': str(refresh.access_token),
                'refresh': str(refresh),
            }

            return Response(data, status=status.HTTP_200_OK)

        except TokenError:
            return Response({
                'error': 'Invalid or expired refresh token'
            }, status=status.HTTP_401_UNAUTHORIZED)


class LogoutView(APIView):
    """
    Logout the current user by blacklisting the refresh token.

    POST /api/auth/logout/
    Headers: Authorization: Bearer <access_token>
    Body: {
        "refresh": "your_refresh_token_here"
    }

    This blacklists the refresh token, preventing it from being used to get new access tokens.
    The mobile app should also delete both tokens from local storage.
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        try:
            refresh_token = request.data.get('refresh')

            if not refresh_token:
                return Response({
                    'error': 'Refresh token is required'
                }, status=status.HTTP_400_BAD_REQUEST)

            token = RefreshToken(refresh_token)
            token.blacklist()

            return Response({
                'message': 'Logout successful. Tokens have been invalidated.'
            }, status=status.HTTP_200_OK)

        except TokenError:
            return Response({
                'error': 'Invalid token'
            }, status=status.HTTP_400_BAD_REQUEST)


class UserProfileView(APIView):
    """
    Get the current authenticated user's profile.

    GET /api/auth/profile/
    Headers: Authorization: Bearer <access_token>

    Returns the authenticated user's details.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        serializer = UserProfileSerializer(request.user)
        return Response(serializer.data, status=status.HTTP_200_OK)


class PushDeviceRegisterView(APIView):
    """
    Register or refresh the current device FCM token.

    POST /api/auth/push/devices/register/
    Headers: Authorization: Bearer <access_token>
    Body: {
        "token": "<fcm_token>",
        "platform": "ios|android",
        "device_id": "optional-stable-device-id",
        "device_name": "optional-friendly-name",
        "app_version": "optional-version",
        "daily_song_enabled": true,
        "messages_enabled": true
    }
    """

    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = PushDeviceRegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        now = timezone.now()

        defaults = {
            'user': request.user,
            'platform': data['platform'],
            'device_id': data.get('device_id') or None,
            'device_name': data.get('device_name', ''),
            'app_version': data.get('app_version', ''),
            'is_active': True,
            'daily_song_enabled': data.get('daily_song_enabled', True),
            'messages_enabled': data.get('messages_enabled', True),
            'last_seen_at': now,
        }

        with transaction.atomic():
            device, created = UserDevicePushToken.objects.update_or_create(
                token=data['token'],
                defaults=defaults,
            )

            if device.device_id:
                UserDevicePushToken.objects.filter(
                    user=request.user,
                    platform=device.platform,
                    device_id=device.device_id,
                    is_active=True,
                ).exclude(id=device.id).update(is_active=False)

        return Response({
            'id': str(device.id),
            'created': created,
            'message': 'Push device registered',
        }, status=status.HTTP_200_OK)


class PushDeviceUnregisterView(APIView):
    """
    Deactivate an FCM token for this user.

    POST /api/auth/push/devices/unregister/
    Headers: Authorization: Bearer <access_token>
    Body: {
        "token": "<fcm_token>"
    }
    """

    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = PushDeviceUnregisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        token = serializer.validated_data['token']

        updated = UserDevicePushToken.objects.filter(
            user=request.user,
            token=token,
            is_active=True,
        ).update(is_active=False)

        return Response({
            'deactivated': updated,
            'message': 'Push device unregistered',
        }, status=status.HTTP_200_OK)


class ChangeEmailView(APIView):
    """
    Change the current user's email address.

    POST /api/auth/change-email/
    Headers: Authorization: Bearer <access_token>
    Body: {
        "current_password": "secret",
        "new_email": "new@example.com"
    }
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = ChangeEmailSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        user = request.user
        if not user.check_password(serializer.validated_data['current_password']):
            return Response(
                {'error': 'Invalid password.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user.email = serializer.validated_data['new_email']
        user.save(update_fields=['email'])

        return Response(
            {'message': 'Email updated successfully.', 'email': user.email},
            status=status.HTTP_200_OK,
        )


class ChangePasswordView(APIView):
    """
    Change the current user's password.
    All existing refresh tokens are blacklisted on success (forces re-login).

    POST /api/auth/change-password/
    Headers: Authorization: Bearer <access_token>
    Body: {
        "current_password": "old_secret",
        "new_password": "new_secret",
        "confirm_new_password": "new_secret"
    }
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = ChangePasswordSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        user = request.user
        if not user.check_password(serializer.validated_data['current_password']):
            return Response(
                {'error': 'Invalid current password.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        with transaction.atomic():
            user.set_password(serializer.validated_data['new_password'])
            user.save(update_fields=['password'])

            # Blacklist all outstanding tokens to force re-login on all devices
            outstanding = OutstandingToken.objects.filter(user=user)
            for token in outstanding:
                try:
                    token.blacklistedtoken
                except Exception:
                    from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken
                    BlacklistedToken.objects.get_or_create(token=token)

        return Response(
            {'message': 'Password updated successfully. Please log in again.'},
            status=status.HTTP_200_OK,
        )


class DataExportView(APIView):
    """
    Export all personal data for the current user (GDPR data portability).

    GET /api/auth/data/export/
    Headers: Authorization: Bearer <access_token>

    Returns a JSON file attachment with all user data.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        from game.models import DailyGameSession, GuessAttempt, RoomUser, RoomMessage, UserPack, PackBundleMessage

        user = request.user

        game_sessions = list(
            DailyGameSession.objects.filter(user=user).values(
                'id', 'room_id', 'correct_guess', 'guesses_made',
                'current_snippet', 'points_earned', 'completed_at', 'created_at',
            )
        )

        guess_attempts = list(
            GuessAttempt.objects.filter(game_session__user=user).values(
                'id', 'game_session_id', 'guessed_title', 'guessed_artist',
                'snippet_number', 'is_correct', 'created_at',
            )
        )

        room_memberships = list(
            RoomUser.objects.filter(user=user).values(
                'room_id', 'room__name', 'joined_at',
            )
        )

        messages_sent = list(
            RoomMessage.objects.filter(user=user).values(
                'id', 'room_id', 'message', 'created_at',
            )
        )

        bundle_messages_sent = list(
            PackBundleMessage.objects.filter(user=user).values(
                'id', 'room_id', 'pack_id', 'message', 'created_at',
            )
        )

        packs_purchased = list(
            UserPack.objects.filter(user=user).values(
                'pack_id', 'pack__name', 'purchased_at',
            )
        )

        coin_history = list(
            CoinTransaction.objects.filter(user=user).values(
                'id', 'amount', 'transaction_type', 'reason', 'created_at',
            )
        )

        payload = {
            'exported_at': timezone.now().isoformat(),
            'profile': {
                'id': str(user.id),
                'username': user.username,
                'email': user.email,
                'coins': user.coins,
                'games_played': user.games_played,
                'games_won': user.games_won,
                'total_points': user.total_points,
                'current_streak': user.current_streak,
                'best_streak': user.best_streak,
                'perfect_games': user.perfect_games,
                'created_at': user.created_at.isoformat(),
            },
            'game_sessions': [
                {**s, 'id': str(s['id']), 'room_id': str(s['room_id']), 'created_at': s['created_at'].isoformat() if s['created_at'] else None}
                for s in game_sessions
            ],
            'guess_attempts': [
                {**g, 'id': str(g['id']), 'game_session_id': str(g['game_session_id']), 'created_at': g['created_at'].isoformat() if g['created_at'] else None}
                for g in guess_attempts
            ],
            'room_memberships': [
                {**r, 'room_id': str(r['room_id']), 'joined_at': r['joined_at'].isoformat() if r['joined_at'] else None}
                for r in room_memberships
            ],
            'messages_sent': [
                {**m, 'id': str(m['id']), 'room_id': str(m['room_id']), 'created_at': m['created_at'].isoformat() if m['created_at'] else None}
                for m in messages_sent
            ],
            'bundle_messages_sent': [
                {**m, 'id': str(m['id']), 'created_at': m['created_at'].isoformat() if m['created_at'] else None}
                for m in bundle_messages_sent
            ],
            'packs_purchased': [
                {**p, 'pack_id': str(p['pack_id']), 'purchased_at': p['purchased_at'].isoformat() if p['purchased_at'] else None}
                for p in packs_purchased
            ],
            'coin_transactions': [
                {**c, 'id': str(c['id']), 'created_at': c['created_at'].isoformat() if c['created_at'] else None}
                for c in coin_history
            ],
        }

        json_bytes = json.dumps(payload, indent=2, default=str).encode('utf-8')
        filename = f"songspot_data_{user.id}.json"

        response = HttpResponse(json_bytes, content_type='application/json')
        response['Content-Disposition'] = f'attachment; filename="{filename}"'
        return response


class DeleteAccountView(APIView):
    """
    Permanently delete the current user's account and all associated data.

    DELETE /api/auth/account/
    Headers: Authorization: Bearer <access_token>
    Body: {
        "password": "secret"
    }
    """
    permission_classes = [IsAuthenticated]

    def delete(self, request):
        serializer = DeleteAccountSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        user = request.user
        if not user.check_password(serializer.validated_data['password']):
            return Response(
                {'error': 'Invalid password.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        with transaction.atomic():
            user.delete()

        return Response(status=status.HTTP_204_NO_CONTENT)
