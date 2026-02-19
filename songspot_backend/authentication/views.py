from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.exceptions import TokenError
from django.contrib.auth import authenticate, get_user_model
from django.db import transaction
from django.utils import timezone
from .models import UserDevicePushToken
from .serializers import (
    UserRegistrationSerializer,
    UserSerializer,
    UserProfileSerializer,
    LoginSerializer,
    PushDeviceRegisterSerializer,
    PushDeviceUnregisterSerializer,
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
