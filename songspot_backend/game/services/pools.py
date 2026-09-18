"""
Category pools, one at a time or all at once.

A category is what every undirected round is served from. Category play reads
one; the all-genre mix, which is the solo default and what every 1v1 match
plays, draws across all of them.

The mix deliberately never reaches past the categories into the open
catalogue. The quality floor still lets ~600k tracks through there, and a
popularity filter cannot tell which of them a player knows. Measured in
September 2026 against 1,269 well-known hits, a Deezer rank-and-followers
filter kept at most half of them, and it favoured French rap, because Deezer's
popularity numbers reflect Deezer's own listeners. The categories are editorial
sets, the only pool known to be recognisable.
"""

import math
import random
from collections import Counter
from datetime import timedelta

from django.db.models import Count, QuerySet
from django.utils import timezone

from game.models import GameScore, Playlist, PlaylistTrack, Track
from game.services import catalog
from game.services.cache_utils import cache_get, cache_set

#: The genre an all-genre session is scored under.
MIX_GENRE = 'mix'

# Categories that were merged into another one but still appear in old scores.
LEGACY_GENRES = {'reggaeton': 'latino', 'latin': 'latino'}

# How far back player choices count towards the mix. Long enough to smooth out
# a quiet week, short enough to follow the audience as it changes.
WEIGHT_WINDOW = timedelta(days=30)
WEIGHTS_TTL = 6 * 60 * 60
WEIGHTS_CACHE_KEY = 'pools:mix-weights:v1'

# The smallest share of the mix any stocked category gets. The weights come
# from a month of history, and a category that was just added or just fixed
# has none yet.
MIN_SHARE = 0.01

# The all-genre mix plays only the better known part of each category. A song
# stays in if it is in the top half of its category by `song_rank`, or if its
# rank alone shows it is well known. It takes both rules, because neither
# works alone:
#
# * A single rank floor reflects Deezer's listeners, not this game's players.
#   At 600k it keeps 536 of Pop's 567 songs, none of Bollywood's 100, and
#   under a third of K-pop.
# * Cutting half of every category ignores how strong each one is. The bottom
#   half of Pop is still Elvis and Fleetwood Mac; the bottom half of Latino is
#   Lennis Rodriguez and Alex Krack.
#
# Measured in September 2026 on the editorial pools, together they keep roughly
# 2,200 of 3,200 songs. Category play is unaffected: a player who picks Rock
# asked for its deep cuts too.
MIX_TOP_SHARE = 0.5
MIX_WELL_KNOWN_RANK = 600_000


def playlist_tracks(playlist_id) -> QuerySet:
    """
    Every track in one category, as a queryset that stays cheap to filter.

    The ids are read out rather than left as a lazy queryset. Nested, this
    becomes a subquery, and Postgres answers it by scanning all 1.6M tracks and
    hash-joining the playlist's ~700 rows onto the result, reading the whole
    catalogue to serve one round. Given the ids as values, it does the join the
    other way round and looks each one up by primary key. Playlists are bounded
    (the largest holds 1328 tracks), so the list is small enough to pass inline.
    """
    track_ids = list(
        PlaylistTrack.objects
        .filter(playlist_id=playlist_id)
        .values_list('track_id', flat=True)
    )
    return Track.objects.filter(id__in=track_ids)


def mix_tracks(playlist_id) -> QuerySet:
    """
    The part of one category that the all-genre mix plays. See MIX_TOP_SHARE.

    A category that has not been ranked yet, with every `song_rank` still 0 as
    it is before the next refresh_catalog run, plays in full rather than not at
    all.
    """
    rows = list(
        PlaylistTrack.objects
        .filter(playlist_id=playlist_id)
        .order_by('-song_rank')
        .values_list('track_id', 'song_rank')
    )
    if not rows or not rows[0][1]:
        return Track.objects.filter(id__in=[track_id for track_id, _ in rows])
    top = math.ceil(len(rows) * MIX_TOP_SHARE)
    kept = [
        track_id for position, (track_id, rank) in enumerate(rows)
        if position < top or rank >= MIX_WELL_KNOWN_RANK
    ]
    return Track.objects.filter(id__in=kept)


def mix_weights() -> dict[str, float]:
    """
    Each stocked category's share of the mix, keyed by playlist id.

    Weighted by what players pick when they choose a category themselves, not
    by how many tracks it holds, because the two are far apart. In September
    2026 Rap Français and Variété Française held a fifth of all category tracks
    but under six percent of category sessions. The players who choose come
    mostly for hip-hop, pop and reggaeton, so weighting by size would serve
    Jacques Brel to a room that came for Bad Bunny. With no history at all, as
    on a fresh install, it falls back to size.
    """
    cached = cache_get(WEIGHTS_CACHE_KEY)
    if cached is not None:
        return cached

    stocked = list(
        Playlist.objects
        .exclude(category__isnull=True).exclude(category='')
        .annotate(size=Count('playlist_tracks'))
        .filter(size__gt=0)
        .values_list('id', 'category', 'size')
    )
    recent = (
        GameScore.objects
        .filter(played_at__gte=timezone.now() - WEIGHT_WINDOW)
        .exclude(genre__isnull=True).exclude(genre='')
        .order_by()
        .values_list('genre')
        .annotate(sessions=Count('id'))
    )
    plays = Counter()
    for genre, sessions in recent:
        plays[LEGACY_GENRES.get(genre, genre)] += sessions
    playlists_per_category = Counter(category for _, category, _ in stocked)

    raw = {
        str(playlist_id): plays[category] / playlists_per_category[category]
        for playlist_id, category, _ in stocked
    }
    if not any(raw.values()):
        raw = {str(playlist_id): size for playlist_id, _, size in stocked}
    total = sum(raw.values())
    if not total:
        # Not cached: the pools may be filling right now, and an empty mix
        # must not outlive the refresh that stocks them.
        return {}

    floored = {pid: max(weight, total * MIN_SHARE) for pid, weight in raw.items()}
    norm = sum(floored.values())
    weights = {pid: weight / norm for pid, weight in floored.items()}
    cache_set(WEIGHTS_CACHE_KEY, weights, WEIGHTS_TTL)
    return weights


def mix_order(rng=random) -> list[str]:
    """
    Every stocked category's playlist id, in a random order weighted by share.

    The first entry is the round's category. The rest are what a round falls
    back on when that category has nothing left for this player. The order uses
    Efraimidis-Spirakis keys, so the whole weighted order takes one pass.
    """
    weights = mix_weights()
    return sorted(
        weights,
        key=lambda pid: rng.random() ** (1 / weights[pid]),
        reverse=True,
    )


def pick_mixed_tracks(count: int, rng=random) -> list[Track]:
    """
    Up to `count` distinct tracks drawn across the categories, for a 1v1 match.

    Each round draws its own category, so one match can move from hip-hop to
    rock. It reads only the database and never calls Deezer, because it runs
    inside the WebSocket handshake (see `consumers._pick_tracks`).
    """
    picks: list[Track] = []
    for _ in range(count):
        for playlist_id in mix_order(rng):
            track = (
                catalog.exclude_songs(
                    catalog.playable(mix_tracks(playlist_id), directed=False),
                    picks,
                )
                .order_by('?')
                .first()
            )
            if track is not None:
                picks.append(track)
                break
        else:
            # Every category is spent. A short match is better than none.
            break
    return picks
