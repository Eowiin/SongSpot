from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.exceptions import TokenError
from django.contrib.auth import authenticate, get_user_model
from .serializers import UserRegistrationSerializer, UserSerializer, UserProfileSerializer, LoginSerializer
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
