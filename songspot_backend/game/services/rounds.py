"""
Round tokens — how the server remembers which song a player is guessing at.

Answer checking moved server-side because the open catalogue made local UUID
comparison wrong (see `matching`). That needs the server to know which track a
guess refers to, and the obvious way — a session table — would mean a write per
round, a cleanup job, and a decision about guests, who have no user row at all.

A signed token avoids all of it. `/next-song/` hands the client an opaque
string carrying the track ID and an issue time; `/guess/` takes it back and
verifies the signature. No state, no table, and guests work exactly like signed-
in players.

It also closes a leak that predates the change: the old `/next-song/` response
included `title` and `artist`, so the answer was sitting in the payload for
anyone reading their own network traffic. The round payload now omits them and
they come back from `/guess/`.
"""

from typing import Optional

from django.core import signing

# Namespaced so a token cannot be replayed against another signed payload.
_SALT = 'songspot.game.round'

# Generous, because it bounds a *round*, not a session: a player may leave the
# app mid-guess and come back. Short enough that a leaked token stops working.
MAX_AGE_SECONDS = 60 * 60 * 6


class InvalidRoundToken(Exception):
    """The token was tampered with, malformed, or too old to trust."""


def issue(track_id: str, *, difficulty: str = '', directed: bool = False) -> str:
    """Mint the token handed out with a round."""
    return signing.dumps(
        {'t': str(track_id), 'd': difficulty, 'a': directed},
        salt=_SALT,
    )


def resolve(token: str) -> dict:
    """
    Read a round token back.

    Raises InvalidRoundToken rather than returning None so a caller cannot
    forget to check and end up treating every guess as correct.
    """
    if not token:
        raise InvalidRoundToken('missing token')
    try:
        payload = signing.loads(token, salt=_SALT, max_age=MAX_AGE_SECONDS)
    except signing.SignatureExpired as exc:
        raise InvalidRoundToken('expired') from exc
    except signing.BadSignature as exc:
        raise InvalidRoundToken('bad signature') from exc
    if not isinstance(payload, dict) or not payload.get('t'):
        raise InvalidRoundToken('malformed payload')
    return payload


def track_id(token: str) -> str:
    return resolve(token)['t']
