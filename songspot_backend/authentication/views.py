import hashlib
import logging

from django.contrib.auth import authenticate, get_user_model
from django.contrib.auth.forms import SetPasswordForm
from django.contrib.auth.tokens import default_token_generator
from django.conf import settings
from django.core.cache import cache
from django.db import transaction
from django.http import HttpResponse
from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework_simplejwt.tokens import RefreshToken
from django.shortcuts import render
from rest_framework_simplejwt.token_blacklist.models import OutstandingToken
from rest_framework_simplejwt.exceptions import TokenError
from django.urls import reverse
from django.utils import timezone, translation
from django.utils.encoding import force_bytes, force_str
from django.utils.http import urlsafe_base64_decode, urlsafe_base64_encode
from django.views import View
from django.core.mail import send_mail
import json
from urllib.parse import urlencode
from .models import UserDevicePushToken
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
    PasswordResetRequestSerializer,
)
from songspot.throttling import AuthRateThrottle, PasswordResetRateThrottle
from songspot.api_errors import error_response, ErrorCode
from .utils import normalize_locale as _normalize_locale

User = get_user_model()
logger = logging.getLogger(__name__)


def _blacklist_outstanding_tokens(user):
    outstanding = OutstandingToken.objects.filter(user=user)
    for token in outstanding:
        try:
            token.blacklistedtoken
        except Exception:
            from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken
            BlacklistedToken.objects.get_or_create(token=token)


def _password_reset_copy(lang):
    if lang == 'fr':
        return {
            'email_subject': 'Reinitialisez votre mot de passe SongSpot',
            'email_body': (
                "Bonjour,\n\n"
                "Nous avons recu une demande de reinitialisation du mot de passe de votre compte SongSpot.\n\n"
                "Choisissez un nouveau mot de passe ici :\n"
                "{reset_url}\n\n"
                "Si vous n'etes pas a l'origine de cette demande, vous pouvez ignorer cet email.\n"
            ),
            'request_success': (
                "Si un compte existe avec cette adresse email, un email de reinitialisation vient d'etre envoye."
            ),
            'page_title': 'SongSpot | Reinitialiser le mot de passe',
            'eyebrow': 'Compte',
            'heading': 'Choisissez un nouveau mot de passe',
            'intro': 'Entrez votre nouveau mot de passe pour finaliser la reinitialisation de votre compte SongSpot.',
            'new_password_label': 'Nouveau mot de passe',
            'confirm_password_label': 'Confirmer le nouveau mot de passe',
            'submit_button': 'Mettre a jour le mot de passe',
            'success_heading': 'Mot de passe mis a jour',
            'success_message': "Votre mot de passe a bien ete reinitialise. Vous pouvez maintenant retourner dans l'app et vous connecter.",
            'invalid_heading': 'Lien invalide ou expire',
            'invalid_message': "Ce lien de reinitialisation n'est plus valide. Demandez un nouvel email depuis l'ecran de connexion.",
        }

    return {
        'email_subject': 'Reset your SongSpot password',
        'email_body': (
            "Hello,\n\n"
            "We received a request to reset the password for your SongSpot account.\n\n"
            "Choose a new password here:\n"
            "{reset_url}\n\n"
            "If you did not request this, you can ignore this email.\n"
        ),
        'request_success': (
            'If an account exists for that email address, a password reset email has been sent.'
        ),
        'page_title': 'SongSpot | Reset Password',
        'eyebrow': 'Account',
        'heading': 'Choose a new password',
        'intro': 'Enter your new password to finish resetting your SongSpot account.',
        'new_password_label': 'New password',
        'confirm_password_label': 'Confirm new password',
        'submit_button': 'Update password',
        'success_heading': 'Password updated',
        'success_message': 'Your password has been reset successfully. You can now go back to the app and sign in.',
        'invalid_heading': 'Invalid or expired link',
        'invalid_message': 'This password reset link is no longer valid. Please request a new email from the login screen.',
    }


def _build_password_reset_url(request, uidb64, token, lang):
    path = reverse(
        'password_reset_confirm',
        kwargs={'uidb64': uidb64, 'token': token},
    )
    base_url = getattr(settings, 'PASSWORD_RESET_BASE_URL', '').strip()
    if base_url:
        reset_url = f"{base_url.rstrip('/')}{path}"
    else:
        reset_url = request.build_absolute_uri(path)

    query = urlencode({'lang': lang})
    separator = '&' if '?' in reset_url else '?'
    return f'{reset_url}{separator}{query}'


def _password_reset_email_cooldown_key(email):
    digest = hashlib.sha256(email.encode('utf-8')).hexdigest()
    return f'password_reset_email:{digest}'


def _set_password_form(user, data, copy):
    form = SetPasswordForm(user, data=data)
    form.fields['new_password1'].label = copy['new_password_label']
    form.fields['new_password2'].label = copy['confirm_password_label']
    form.fields['new_password1'].widget.attrs.update(
        {
            'class': 'reset-input',
            'placeholder': copy['new_password_label'],
            'autocomplete': 'new-password',
        }
    )
    form.fields['new_password2'].widget.attrs.update(
        {
            'class': 'reset-input',
            'placeholder': copy['confirm_password_label'],
            'autocomplete': 'new-password',
        }
    )
    return form


def _get_user_from_uid(uidb64):
    try:
        user_id = force_str(urlsafe_base64_decode(uidb64))
        return User.objects.get(pk=user_id)
    except (TypeError, ValueError, OverflowError, User.DoesNotExist):
        return None

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

        return error_response(
            code=ErrorCode.INVALID_CREDENTIALS,
            message='Invalid credentials',
            status_code=status.HTTP_401_UNAUTHORIZED,
        )


class PasswordResetRequestView(APIView):
    """
    Send a password reset email if the account exists.

    POST /api/auth/password-reset/request/
    Body: {
        "email": "user@example.com",
        "locale": "fr"
    }
    """

    permission_classes = [AllowAny]
    throttle_classes = [PasswordResetRateThrottle]

    def post(self, request):
        serializer = PasswordResetRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        email = serializer.validated_data['email']
        lang = _normalize_locale(serializer.validated_data.get('locale'))
        copy = _password_reset_copy(lang)
        cooldown_seconds = max(
            int(getattr(settings, 'PASSWORD_RESET_EMAIL_COOLDOWN_SECONDS', 900)),
            0,
        )
        cooldown_key = _password_reset_email_cooldown_key(email)

        if cooldown_seconds and cache.get(cooldown_key):
            return Response(
                {'message': copy['request_success']},
                status=status.HTTP_200_OK,
            )

        users = User.objects.filter(email__iexact=email, is_active=True)
        try:
            for user in users:
                uidb64 = urlsafe_base64_encode(force_bytes(user.pk))
                token = default_token_generator.make_token(user)
                reset_url = _build_password_reset_url(request, uidb64, token, lang)
                send_mail(
                    subject=copy['email_subject'],
                    message=copy['email_body'].format(reset_url=reset_url),
                    from_email=settings.DEFAULT_FROM_EMAIL,
                    recipient_list=[user.email],
                )
        except Exception:
            logger.exception('Unable to send password reset email.')
            return error_response(
                code=ErrorCode.PASSWORD_RESET_UNAVAILABLE,
                message='Password reset email is currently unavailable.',
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            )

        if cooldown_seconds:
            cache.set(cooldown_key, True, timeout=cooldown_seconds)

        return Response(
            {'message': copy['request_success']},
            status=status.HTTP_200_OK,
        )


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
            return error_response(
                code=ErrorCode.REFRESH_TOKEN_REQUIRED,
                message='Refresh token is required',
                status_code=status.HTTP_400_BAD_REQUEST,
            )

        try:
            refresh = RefreshToken(refresh_token)

            data = {
                'access': str(refresh.access_token),
                'refresh': str(refresh),
            }

            return Response(data, status=status.HTTP_200_OK)

        except TokenError:
            return error_response(
                code=ErrorCode.INVALID_OR_EXPIRED_REFRESH_TOKEN,
                message='Invalid or expired refresh token',
                status_code=status.HTTP_401_UNAUTHORIZED,
            )


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
                return error_response(
                    code=ErrorCode.REFRESH_TOKEN_REQUIRED,
                    message='Refresh token is required',
                    status_code=status.HTTP_400_BAD_REQUEST,
                )

            token = RefreshToken(refresh_token)
            token.blacklist()

            return Response({
                'message': 'Logout successful. Tokens have been invalidated.'
            }, status=status.HTTP_200_OK)

        except TokenError:
            return error_response(
                code=ErrorCode.INVALID_TOKEN,
                message='Invalid token',
                status_code=status.HTTP_400_BAD_REQUEST,
            )


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
        serializer = ChangeEmailSerializer(
            data=request.data,
            context={'user': request.user},
        )
        serializer.is_valid(raise_exception=True)

        user = request.user
        if not user.check_password(serializer.validated_data['current_password']):
            return error_response(
                code=ErrorCode.INVALID_PASSWORD,
                message='Invalid password.',
                status_code=status.HTTP_400_BAD_REQUEST,
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
            return error_response(
                code=ErrorCode.INVALID_CURRENT_PASSWORD,
                message='Invalid current password.',
                status_code=status.HTTP_400_BAD_REQUEST,
            )

        with transaction.atomic():
            user.set_password(serializer.validated_data['new_password'])
            user.save(update_fields=['password'])
            _blacklist_outstanding_tokens(user)

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
        from django.db.models import Q
        from game.models import DuelMatch, FavouriteArtist, GameScore, UserBest, UserElo

        user = request.user

        game_scores = list(
            GameScore.objects.filter(user=user).values(
                'id', 'genre', 'artist_filter', 'difficulty',
                'songs_played', 'songs_correct', 'best_streak',
                'total_score', 'is_partial', 'played_at',
            )
        )

        favourite_artists = list(
            FavouriteArtist.objects.filter(user=user).values(
                'artist_name', 'created_at',
            )
        )

        duels = list(
            DuelMatch.objects.filter(Q(player1=user) | Q(player2=user)).values(
                'id', 'status', 'total_rounds', 'current_round',
                'player1_id', 'player2_id', 'player1_score', 'player2_score',
                'winner_id', 'created_at',
            )
        )

        elo = UserElo.objects.filter(user=user).values(
            'elo', 'wins', 'losses', 'draws', 'updated_at',
        ).first()

        best = UserBest.objects.filter(user=user).values(
            'best_score_overall', 'best_streak_overall',
            'total_songs_played', 'total_songs_correct', 'per_genre',
        ).first()

        payload = {
            'exported_at': timezone.now().isoformat(),
            'profile': {
                'id': str(user.id),
                'username': user.username,
                'email': user.email,
                'games_played': user.games_played,
                'games_won': user.games_won,
                'total_points': user.total_points,
                'current_streak': user.current_streak,
                'best_streak': user.best_streak,
                'perfect_games': user.perfect_games,
                'created_at': user.created_at.isoformat(),
            },
            'game_scores': [
                {**s, 'id': str(s['id']), 'played_at': s['played_at'].isoformat() if s['played_at'] else None}
                for s in game_scores
            ],
            'favourite_artists': [
                {**a, 'created_at': a['created_at'].isoformat() if a['created_at'] else None}
                for a in favourite_artists
            ],
            'duels': [
                {
                    **d,
                    'id': str(d['id']),
                    'player1_id': str(d['player1_id']),
                    'player2_id': str(d['player2_id']),
                    'winner_id': str(d['winner_id']) if d['winner_id'] else None,
                    'created_at': d['created_at'].isoformat() if d['created_at'] else None,
                }
                for d in duels
            ],
            'elo': (
                {**elo, 'updated_at': elo['updated_at'].isoformat() if elo['updated_at'] else None}
                if elo else None
            ),
            'personal_bests': best,
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
            return error_response(
                code=ErrorCode.INVALID_PASSWORD,
                message='Invalid password.',
                status_code=status.HTTP_400_BAD_REQUEST,
            )

        with transaction.atomic():
            user.delete()

        return Response(status=status.HTTP_204_NO_CONTENT)


class PasswordResetConfirmPageView(View):
    def _render_page(self, request, *, uidb64, token, form=None, success=False):
        lang = _normalize_locale(
            request.POST.get('lang')
            or request.GET.get('lang')
            or request.headers.get('Accept-Language')
        )
        copy = _password_reset_copy(lang)
        user = _get_user_from_uid(uidb64)
        validlink = bool(user and default_token_generator.check_token(user, token))

        if validlink and form is None and not success:
            with translation.override(lang):
                form = _set_password_form(user, None, copy)

        return render(
            request,
            'site/password_reset_confirm.html',
            {
                'active_page': None,
                'lang': lang,
                'copy': copy,
                'form': form,
                'success': success,
                'validlink': validlink,
            },
        )

    def get(self, request, uidb64, token):
        return self._render_page(request, uidb64=uidb64, token=token)

    def post(self, request, uidb64, token):
        lang = _normalize_locale(
            request.POST.get('lang')
            or request.GET.get('lang')
            or request.headers.get('Accept-Language')
        )
        copy = _password_reset_copy(lang)
        user = _get_user_from_uid(uidb64)
        if not user or not default_token_generator.check_token(user, token):
            return self._render_page(request, uidb64=uidb64, token=token)

        with translation.override(lang):
            form = _set_password_form(user, request.POST, copy)
            is_valid = form.is_valid()
        if is_valid:
            with transaction.atomic():
                form.save()
                _blacklist_outstanding_tokens(user)
            return self._render_page(
                request,
                uidb64=uidb64,
                token=token,
                success=True,
            )

        return self._render_page(
            request,
            uidb64=uidb64,
            token=token,
            form=form,
        )
