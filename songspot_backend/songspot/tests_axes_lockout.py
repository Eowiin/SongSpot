"""Regression tests for the site-wide axes lockout of 2026-08-28.

The backend sits behind nginx, so REMOTE_ADDR is 127.0.0.1 on every request.
With the axes defaults that made a single lockout bucket for the entire site:
five cumulative failures from anyone locked out everyone, and because failures
arriving during a lockout pushed the cool-off deadline forward, the lockout
never expired.
"""
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.test import RequestFactory, TestCase, override_settings
from django.urls import reverse

from axes.helpers import get_client_ip_address
from axes.models import AccessAttempt

from songspot.client_ip import client_ip
from songspot.throttling import AuthRateThrottle

User = get_user_model()


PROXY = '127.0.0.1'
ALICE_IP = '203.0.113.9'
BOT_IP = '198.51.100.7'


class ClientIpTests(TestCase):
    def setUp(self):
        self.factory = RequestFactory()

    def _request(self, **meta):
        return self.factory.post('/api/auth/login/', **meta)

    def test_returns_address_nginx_saw_not_the_proxy(self):
        request = self._request(REMOTE_ADDR=PROXY, HTTP_X_FORWARDED_FOR=ALICE_IP)
        self.assertEqual(client_ip(request), ALICE_IP)

    def test_ignores_client_supplied_prefix(self):
        """A client sending its own X-Forwarded-For must not shift the result."""
        request = self._request(
            REMOTE_ADDR=PROXY,
            HTTP_X_FORWARDED_FOR=f'10.0.0.1, 8.8.8.8, {ALICE_IP}',
        )
        self.assertEqual(client_ip(request), ALICE_IP)

    def test_falls_back_to_remote_addr(self):
        request = self._request(REMOTE_ADDR=ALICE_IP)
        self.assertEqual(client_ip(request), ALICE_IP)

    def test_axes_uses_the_callable(self):
        """The wiring matters as much as the function: axes must actually call it."""
        request = self._request(REMOTE_ADDR=PROXY, HTTP_X_FORWARDED_FOR=ALICE_IP)
        self.assertEqual(get_client_ip_address(request), ALICE_IP)


@override_settings(AXES_FAILURE_LIMIT=5)
class LockoutIsolationTests(TestCase):
    """Each account keeps its own failure budget, and so does each address."""

    def setUp(self):
        cache.clear()
        # The endpoint is throttled at 5/minute and would answer 429 before axes
        # sees the sixth attempt. THROTTLE_RATES is a class attribute bound at
        # import, so override_settings cannot reach it. The throttle is a real
        # second line of defence; it is just not what these tests measure.
        no_throttle = patch.object(AuthRateThrottle, 'get_rate', return_value=None)
        no_throttle.start()
        self.addCleanup(no_throttle.stop)
        self.url = reverse('authentication:login')
        self.alice = User.objects.create_user(
            email='alice@example.com', username='alice', password='correct-horse-battery'
        )

    def _login(self, email, password, ip):
        return self.client.post(
            self.url,
            {'email': email, 'password': password},
            HTTP_X_FORWARDED_FOR=ip,
            REMOTE_ADDR=PROXY,
        )

    def _exhaust(self, email, ip):
        for _ in range(5):
            self._login(email, 'wrong-password', ip)

    def test_attempts_are_recorded_against_the_real_address(self):
        self._login('alice@example.com', 'wrong-password', ALICE_IP)
        attempt = AccessAttempt.objects.get()
        self.assertEqual(attempt.ip_address, ALICE_IP)
        self.assertNotEqual(attempt.ip_address, PROXY)

    def test_a_bot_hammering_another_account_does_not_lock_alice_out(self):
        """This is the incident: 107 bot attempts had locked out every account."""
        self._exhaust('admin@example.com', BOT_IP)
        response = self._login('alice@example.com', 'correct-horse-battery', ALICE_IP)
        self.assertEqual(response.status_code, 200)

    def test_a_bot_on_alices_account_does_not_lock_her_own_address_out(self):
        """Locking on the pair means an attacker cannot lock a user out remotely."""
        self._exhaust('alice@example.com', BOT_IP)
        response = self._login('alice@example.com', 'correct-horse-battery', ALICE_IP)
        self.assertEqual(response.status_code, 200)

    def test_real_brute_force_on_one_pair_is_still_locked(self):
        """The protection must survive the fix: the right password is refused.

        The status is 401 rather than the 403 axes serves on the admin site.
        LoginView passes the DRF Request to authenticate(), and DRF proxies
        attribute reads but not writes, so the axes_locked_out flag lands on the
        wrapper and AxesMiddleware never sees it on the underlying HttpRequest.
        The lockout itself holds, which is what this test pins down; the
        misleading status code is tracked separately.
        """
        self._exhaust('alice@example.com', ALICE_IP)
        response = self._login('alice@example.com', 'correct-horse-battery', ALICE_IP)
        self.assertEqual(response.status_code, 401)
        self.assertNotIn('tokens', response.json())


@override_settings(AXES_FAILURE_LIMIT=5)
class CoolOffTests(TestCase):
    """Failures arriving during a lockout must not extend it."""

    def setUp(self):
        cache.clear()
        # The endpoint is throttled at 5/minute and would answer 429 before axes
        # sees the sixth attempt. THROTTLE_RATES is a class attribute bound at
        # import, so override_settings cannot reach it. The throttle is a real
        # second line of defence; it is just not what these tests measure.
        no_throttle = patch.object(AuthRateThrottle, 'get_rate', return_value=None)
        no_throttle.start()
        self.addCleanup(no_throttle.stop)
        self.url = reverse('authentication:login')
        User.objects.create_user(
            email='alice@example.com', username='alice', password='correct-horse-battery'
        )

    def _login(self, password):
        return self.client.post(
            self.url,
            {'email': 'alice@example.com', 'password': password},
            HTTP_X_FORWARDED_FOR=ALICE_IP,
            REMOTE_ADDR=PROXY,
        )

    def test_further_failures_do_not_push_the_deadline_forward(self):
        for _ in range(5):
            self._login('wrong-password')
        locked_at = AccessAttempt.objects.get().attempt_time

        for _ in range(10):
            self._login('wrong-password')

        self.assertEqual(AccessAttempt.objects.get().attempt_time, locked_at)
