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
