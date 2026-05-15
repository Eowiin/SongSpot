from django.core.cache import cache
from django.core import mail
from django.test import TestCase
from django.urls import reverse
from django.test.utils import override_settings
from django.utils.encoding import force_bytes
from django.utils.http import urlsafe_base64_encode
from django.contrib.auth.tokens import default_token_generator
from rest_framework.test import APITestCase, APIClient
from rest_framework import status
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken
from .models import User


class UserModelTests(TestCase):
    """Tests for the custom User model."""

    def test_create_user(self):
        """Test creating a regular user."""
        user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='testpass123'
        )
        self.assertEqual(user.email, 'test@example.com')
        self.assertEqual(user.username, 'testuser')
        self.assertTrue(user.is_active)
        self.assertFalse(user.is_staff)
        self.assertTrue(user.check_password('testpass123'))

    def test_create_user_without_email_raises_error(self):
        """Test that creating a user without email raises an error."""
        with self.assertRaises(ValueError):
            User.objects.create_user(
                username='testuser',
                email='',
                password='testpass123'
            )

    def test_create_superuser(self):
        """Test creating a superuser."""
        admin = User.objects.create_superuser(
            username='admin',
            email='admin@example.com',
            password='adminpass123'
        )
        self.assertTrue(admin.is_staff)
        self.assertTrue(admin.is_superuser)

    def test_user_string_representation(self):
        """Test the string representation of a user."""
        user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='testpass123'
        )
        self.assertEqual(str(user), 'test@example.com')

    def test_create_user_normalizes_email_to_lowercase(self):
        user = User.objects.create_user(
            username='testuser',
            email='Test@Example.COM',
            password='testpass123',
        )
        self.assertEqual(user.email, 'test@example.com')


class RegisterViewTests(APITestCase):
    """Tests for user registration endpoint."""

    def setUp(self):
        cache.clear()
        self.register_url = '/api/auth/register/'

    def test_register_user_success(self):
        """Test successful user registration."""
        data = {
            'email': 'newuser@example.com',
            'username': 'newuser',
            'password': 'securepass123',
            'password_confirm': 'securepass123'
        }
        response = self.client.post(self.register_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertIn('user', response.data)
        self.assertIn('tokens', response.data)
        self.assertIn('access', response.data['tokens'])
        self.assertIn('refresh', response.data['tokens'])
        self.assertEqual(response.data['user']['email'], 'newuser@example.com')

    def test_register_user_password_mismatch(self):
        """Test registration fails when passwords don't match."""
        data = {
            'email': 'newuser@example.com',
            'username': 'newuser',
            'password': 'securepass123',
            'password_confirm': 'differentpass'
        }
        response = self.client.post(self.register_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_register_user_duplicate_email(self):
        """Test registration fails with duplicate email."""
        User.objects.create_user(
            username='existing',
            email='existing@example.com',
            password='testpass123'
        )
        data = {
            'email': 'existing@example.com',
            'username': 'newuser',
            'password': 'securepass123',
            'password_confirm': 'securepass123'
        }
        response = self.client.post(self.register_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_register_user_missing_fields(self):
        """Test registration fails with missing fields."""
        data = {
            'email': 'newuser@example.com'
        }
        response = self.client.post(self.register_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_register_user_lowercases_email(self):
        data = {
            'email': 'NewUser@Example.COM',
            'username': 'newuser',
            'password': 'securepass123',
            'password_confirm': 'securepass123'
        }
        response = self.client.post(self.register_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['user']['email'], 'newuser@example.com')


class LoginViewTests(APITestCase):
    """Tests for user login endpoint."""

    def setUp(self):
        cache.clear()
        self.login_url = '/api/auth/login/'
        self.user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='testpass123'
        )

    def test_login_success(self):
        """Test successful login."""
        data = {
            'email': 'test@example.com',
            'password': 'testpass123'
        }
        response = self.client.post(self.login_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('user', response.data)
        self.assertIn('tokens', response.data)
        self.assertIn('access', response.data['tokens'])
        self.assertIn('refresh', response.data['tokens'])

    def test_login_wrong_password(self):
        """Test login fails with wrong password."""
        data = {
            'email': 'test@example.com',
            'password': 'wrongpassword'
        }
        response = self.client.post(self.login_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_login_nonexistent_user(self):
        """Test login fails with nonexistent email."""
        data = {
            'email': 'nonexistent@example.com',
            'password': 'testpass123'
        }
        response = self.client.post(self.login_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_login_missing_fields(self):
        """Test login fails with missing fields."""
        data = {
            'email': 'test@example.com'
        }
        response = self.client.post(self.login_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_login_is_case_insensitive_for_email(self):
        data = {
            'email': 'Test@Example.COM',
            'password': 'testpass123'
        }
        response = self.client.post(self.login_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)


class LogoutViewTests(APITestCase):
    """Tests for user logout endpoint."""

    def setUp(self):
        cache.clear()
        self.logout_url = '/api/auth/logout/'
        self.user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='testpass123'
        )
        self.refresh = RefreshToken.for_user(self.user)
        self.access_token = str(self.refresh.access_token)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.access_token}')

    def test_logout_success(self):
        """Test successful logout."""
        data = {
            'refresh': str(self.refresh)
        }
        response = self.client.post(self.logout_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_logout_without_refresh_token(self):
        """Test logout fails without refresh token."""
        response = self.client.post(self.logout_url, {}, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_logout_unauthenticated(self):
        """Test logout fails without authentication."""
        self.client.credentials()  # Remove auth
        data = {
            'refresh': str(self.refresh)
        }
        response = self.client.post(self.logout_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)


class RefreshTokenViewTests(APITestCase):
    """Tests for token refresh endpoint."""

    def setUp(self):
        cache.clear()
        self.refresh_url = '/api/auth/token/refresh/'
        self.user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='testpass123'
        )
        self.refresh = RefreshToken.for_user(self.user)

    def test_refresh_token_success(self):
        """Test successful token refresh."""
        data = {
            'refresh': str(self.refresh)
        }
        response = self.client.post(self.refresh_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)
        self.assertIn('refresh', response.data)

    def test_refresh_token_missing(self):
        """Test refresh fails without token."""
        response = self.client.post(self.refresh_url, {}, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_refresh_token_invalid(self):
        """Test refresh fails with invalid token."""
        data = {
            'refresh': 'invalid-token'
        }
        response = self.client.post(self.refresh_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)


@override_settings(
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend',
    DEFAULT_FROM_EMAIL='no-reply@songspot.test',
)
class PasswordResetFlowTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.request_url = '/api/auth/password-reset/request/'
        self.user = User.objects.create_user(
            username='reset-user',
            email='reset@example.com',
            password='oldpass123A',
        )

    def test_password_reset_request_sends_email_and_includes_lang(self):
        response = self.client.post(
            self.request_url,
            {'email': 'Reset@Example.com', 'locale': 'fr'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(mail.outbox), 1)
        self.assertIn('/reset-password/', mail.outbox[0].body)
        self.assertIn('lang=fr', mail.outbox[0].body)

    def test_password_reset_request_is_silent_for_unknown_email(self):
        response = self.client.post(
            self.request_url,
            {'email': 'missing@example.com'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(mail.outbox), 0)

    def test_password_reset_request_enforces_email_cooldown(self):
        first = self.client.post(
            self.request_url,
            {'email': 'reset@example.com'},
            format='json',
        )
        second = self.client.post(
            self.request_url,
            {'email': 'Reset@Example.com'},
            format='json',
        )

        self.assertEqual(first.status_code, status.HTTP_200_OK)
        self.assertEqual(second.status_code, status.HTTP_200_OK)
        self.assertEqual(len(mail.outbox), 1)

    def test_password_reset_request_ip_throttle_blocks_after_three_attempts(self):
        responses = []
        for email in (
            'one@example.com',
            'two@example.com',
            'three@example.com',
            'four@example.com',
        ):
            responses.append(
                self.client.post(
                    self.request_url,
                    {'email': email},
                    format='json',
                )
            )

        self.assertEqual(responses[0].status_code, status.HTTP_200_OK)
        self.assertEqual(responses[1].status_code, status.HTTP_200_OK)
        self.assertEqual(responses[2].status_code, status.HTTP_200_OK)
        self.assertEqual(responses[3].status_code, status.HTTP_429_TOO_MANY_REQUESTS)

    def test_password_reset_confirm_updates_password_and_blacklists_tokens(self):
        refresh = RefreshToken.for_user(self.user)
        reset_url = reverse(
            'password_reset_confirm',
            kwargs={
                'uidb64': urlsafe_base64_encode(force_bytes(self.user.pk)),
                'token': default_token_generator.make_token(self.user),
            },
        )
        response = self.client.post(
            f'{reset_url}?lang=en',
            {
                'lang': 'en',
                'new_password1': 'BrandNewPass123',
                'new_password2': 'BrandNewPass123',
            },
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password('BrandNewPass123'))
        self.assertTrue(
            BlacklistedToken.objects.filter(token__user=self.user).exists()
        )


class UserProfileViewTests(APITestCase):
    """Tests for user profile endpoint."""

    def setUp(self):
        cache.clear()
        self.profile_url = '/api/auth/profile/'
        self.user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='testpass123'
        )
        self.refresh = RefreshToken.for_user(self.user)
        self.access_token = str(self.refresh.access_token)

    def test_get_profile_authenticated(self):
        """Test getting profile when authenticated."""
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.access_token}')
        response = self.client.get(self.profile_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['email'], 'test@example.com')
        self.assertEqual(response.data['username'], 'testuser')

    def test_get_profile_unauthenticated(self):
        """Test getting profile fails when not authenticated."""
        response = self.client.get(self.profile_url)
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
