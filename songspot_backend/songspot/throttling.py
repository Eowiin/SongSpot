"""
Custom throttle classes for rate limiting specific endpoints.
"""

from rest_framework.throttling import UserRateThrottle, AnonRateThrottle


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


class GameSearchThrottle(AnonRateThrottle):
    """
    Permissive limit for gameplay endpoints (track search, next song).
    Search fires on every keystroke so the default anon limit is too tight.
    """
    scope = 'game_search'
