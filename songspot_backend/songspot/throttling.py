"""
Custom throttle classes for rate limiting specific endpoints.
"""

from rest_framework.throttling import AnonRateThrottle, SimpleRateThrottle, UserRateThrottle


class AuthRateThrottle(AnonRateThrottle):
    """
    Rate limit for authentication endpoints (login, register).
    Stricter limits to prevent brute force attacks.
    """
    scope = 'auth'


class PasswordResetRateThrottle(AnonRateThrottle):
    """
    Stricter rate limit for password reset email requests.
    """
    scope = 'password_reset'


class GuessRateThrottle(UserRateThrottle):
    """
    Rate limit for game guess submissions.
    Prevents automated guessing.
    """
    scope = 'guess'


class MessageRateThrottle(UserRateThrottle):
    """
    Rate limit for chat messages.
    Prevents spam in chat rooms.
    """
    scope = 'message'


class BurstRateThrottle(UserRateThrottle):
    """
    Short burst rate limit for sensitive operations.
    """
    scope = 'burst'
    rate = '3/second'


class BugReportRateThrottle(SimpleRateThrottle):
    """
    Limit bug reports per account, or per IP for guests.

    Unlike AnonRateThrottle and UserRateThrottle, this one covers both kinds of
    caller. Every report sends an email, so a signed-in account must not be
    able to send an unlimited number of them either.
    """
    scope = 'bug_report'

    def get_cache_key(self, request, view):
        if request.user and request.user.is_authenticated:
            ident = f'user-{request.user.pk}'
        else:
            ident = f'ip-{self.get_ident(request)}'
        return self.cache_format % {'scope': self.scope, 'ident': ident}


class GameSearchThrottle(AnonRateThrottle):
    """
    Permissive limit for gameplay endpoints (track search, next song).
    Search fires on every keystroke so the default anon limit is too tight.
    """
    scope = 'game_search'
