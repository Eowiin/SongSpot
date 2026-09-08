"""
The catalogue: Deezer as the source of truth, the database as its cache.

The game used to play from a closed list — 206 artists in
`curated_artists.json`, seeded offline. An artist not on that list did not
exist, and neither did any song outside an artist's seeded top ten. This module
inverts that: anything Deezer knows is playable, and every track the game
touches is written through to `tracks` on the way past. The catalogue grows
itself with use, so the hot paths keep serving from Postgres rather than from
a live API call.

## Two kinds of pick, two different rules

The distinction that runs through this file is whether the *player* chose the
artist:

* **Directed** — the player picked an artist. No popularity threshold at all.
  We pull that exact Deezer artist entity's discography, so an act with 200
  fans plays perfectly well and no stray cover can turn up: we are no longer
  searching by name.
* **Undirected** — a category, a duel, anything where the game chooses. Here
  the song has to be recognisable or the round is unplayable, so the quality
  floor from `CatalogSetting` applies.

Getting this backwards in either direction is a visible bug: a floor on
directed picks silently blocks the niche artist a player deliberately asked
for, and no floor on undirected picks fills a Pop round with karaoke.

## What is filtered, and what never is

Filtering applies to what the game *plays at you*. It never applies to what it
*accepts as an answer* — a live cut is a poor snippet but a perfectly correct
guess. Answer acceptance lives in `matching.py` and deliberately knows nothing
about ranks or fan counts.
"""

import hashlib
import logging
import math
from datetime import timedelta
from typing import Iterable, Optional

from django.db import IntegrityError, transaction
from django.db.models import F, Q, QuerySet
from django.utils import timezone

from ..models import Artist, CatalogSetting, SearchMiss, Track
from . import background
from .cache_utils import cache_add, cache_delete
from .deezer_http import DeezerHttp
from .deezer_service import DeezerService
from .matching import (
    answer_matches,
    is_junk_artist,
    is_variant_title,
    normalize_artist,
    normalize_query,
    normalize_title,
    song_key,
)

logger = logging.getLogger(__name__)

# Fields refreshed on an existing row when a richer payload arrives. The
# player-visible identity (title, artist) is never overwritten: it is what the
# normalised answer keys were built from.
_REFRESHABLE = (
    'cover_url',
    'release_year', 'genre', 'rank', 'deezer_artist_id',
)


def settings_row() -> CatalogSetting:
    return CatalogSetting.get_solo()


# ── Artists ──────────────────────────────────────────────────────────────────

def upsert_artist(payload: dict) -> Optional[Artist]:
    """Persist a Deezer artist payload. Returns None for an unusable payload."""
    deezer_id = payload.get('id')
    name = (payload.get('name') or '').strip()
    if not deezer_id or not name:
        return None

    picture = (
        payload.get('picture_xl') or payload.get('picture_big') or
        payload.get('picture_medium') or payload.get('picture_small') or
        payload.get('picture') or None
    )

    artist, created = Artist.objects.get_or_create(
        deezer_id=deezer_id,
        defaults={
            'name': name,
            'picture_url': picture,
            'nb_fan': payload.get('nb_fan') or 0,
        },
    )
    if created:
        return artist

    changed = []
    # `nb_fan` is absent from search payloads and present on /artist/{id}; only
    # let a real number move it, so a lighter payload cannot zero it out.
    if payload.get('nb_fan') and payload['nb_fan'] != artist.nb_fan:
        artist.nb_fan = payload['nb_fan']
        changed.append('nb_fan')
    if picture and picture != artist.picture_url:
        artist.picture_url = picture
        changed.append('picture_url')
    if name != artist.name:
        artist.name = name
        changed.extend(['name', 'norm_name'])
    if changed:
        artist.save()
    return artist


# ── Enrichment: growing the catalogue without making anyone wait ─────────────
#
# Deezer is an ETL dependency, not a request dependency. The search box answers
# from Postgres; the live call that teaches the catalogue a new song happens
# after the response has gone out.
#
# The one exception is a query with *no* local answer at all. That is precisely
# the case the open catalogue was built for — a player looking for an act we
# have never held — and showing them an empty list to save a single API call is
# the wrong trade. So an empty result pays one live call, once, and the
# deduplication below means it stays once.

# Below this many results, the catalogue clearly does not know the query well.
ENRICH_BELOW = 5

# How long a query stays marked as enriched. Long, because the answer barely
# changes: "despacito" gets one live call a week across every player, not four
# hundred a day. This is what turns enrichment from a per-request cost into a
# per-query one.
ENRICH_DEDUP_TTL = 60 * 60 * 24 * 7

# A player is waiting on the synchronous path, so the Deezer budget there is
# tighter than the default. Missing the window costs an empty dropdown, which
# is what they had anyway.
SYNC_MAX_WAIT = 1.0


def _enrich_key(kind: str, query: str) -> str:
    # Hashed rather than interpolated: a query contains spaces and arbitrary
    # punctuation, which some cache backends reject and all of them make
    # awkward to read back.
    digest = hashlib.sha1(normalize_query(query).encode()).hexdigest()[:16]
    return f'enrich:{kind}:{digest}'


def _claim(kind: str, query: str) -> bool:
    """True if this caller is the one that should enrich `query`."""
    return cache_add(_enrich_key(kind, query), 1, timeout=ENRICH_DEDUP_TTL)


def _enrich_later(fn, kind: str, query: str) -> None:
    """Queue enrichment to run after the response. Silent if already claimed."""
    if not _claim(kind, query):
        return
    if not background.submit(fn, query):
        # Dropped, so release the claim: holding it for a week would mean this
        # query is never enriched at all, on the strength of one busy moment.
        cache_delete(_enrich_key(kind, query))


def _enrich_now(fn, kind: str, query: str) -> Optional[list]:
    """
    Enrich inline, for a query with nothing to show.

    Returns what was imported, or None if the query was already claimed or the
    call failed. Returning the rows matters: a local query cannot always
    reproduce Deezer's matching — searching `band` returns "Karaoke Kings",
    which no `icontains` on our side will ever find — so the caller needs the
    option of using these directly rather than re-reading the table.

    A claimed query that is still empty has been looked up before and Deezer
    genuinely has nothing; calling again would spend quota to learn that twice.
    """
    if not _claim(kind, query):
        return None
    try:
        return fn(query, max_wait=SYNC_MAX_WAIT)
    except Exception:
        logger.exception('inline enrichment failed for %r', query)
        cache_delete(_enrich_key(kind, query))
        return None


def _record_miss(query: str) -> None:
    """
    Remember a query the catalogue could not answer at all.

    These are the crawler's seeds. A missing artist is invisible from the
    inside — nobody files a bug for a search that returned nothing, they leave
    a one-star review — so this table is the only signal that says which part
    of the catalogue to grow next.
    """
    norm = normalize_query(query)[:255]
    if not norm:
        return
    try:
        _, created = SearchMiss.objects.get_or_create(
            norm_query=norm, defaults={'query': query[:255]},
        )
        if not created:
            SearchMiss.objects.filter(norm_query=norm).update(hits=F('hits') + 1)
    except IntegrityError:
        # Another worker recorded the same miss first.
        pass


def sync_artists_from_tracks(infos: Iterable[dict]) -> None:
    """
    Keep `artists` complete as tracks arrive.

    Artist artwork used to be copied onto every track row; migration 0016 moved
    it to `artists`, which only works if every artist a track mentions actually
    has a row there. Chart and album imports carry the artist's id, name and
    picture in the track payload but never went through `upsert_artist`, so
    without this an artist could own five hundred tracks and still be missing
    from artist search.

    Two queries regardless of batch size: one read, one write. Names are never
    overwritten — a track payload credits whoever is billed on that release,
    which for a feature is not the artist the row is about.
    """
    names: dict[int, str] = {}
    pictures: dict[int, str] = {}
    for info in infos:
        artist_id = info.get('deezer_artist_id')
        if not artist_id:
            continue
        if info.get('artist'):
            names.setdefault(artist_id, info['artist'])
        if info.get('artist_picture_url'):
            pictures.setdefault(artist_id, info['artist_picture_url'])

    if not names:
        return

    existing = {
        a.deezer_id: a for a in Artist.objects.filter(deezer_id__in=list(names))
    }

    created, updated = [], []
    for artist_id, name in names.items():
        artist = existing.get(artist_id)
        picture = pictures.get(artist_id)
        if artist is None:
            new = Artist(deezer_id=artist_id, name=name, picture_url=picture)
            # bulk_create skips save(), which is where these are maintained.
            new.norm_name = normalize_artist(name)
            new.is_junk = is_junk_artist(name)
            created.append(new)
        elif picture and not artist.picture_url:
            artist.picture_url = picture
            updated.append(artist)

    if created:
        Artist.objects.bulk_create(created, ignore_conflicts=True, batch_size=500)
    if updated:
        Artist.objects.bulk_update(updated, ['picture_url'], batch_size=500)


def search_artists(query: str, limit: int = 25) -> list[Artist]:
    """
    Artist autocomplete over the whole of Deezer, ranked by followers.

    Deezer's own ordering cannot be used as-is: `q=weeknd` puts "Weeknd"
    (2 101 fans) above "The Weeknd" (14 659 544) and mixes in "The Retro
    Weeknd", a covers act. Sorting on `nb_fan` is what puts the artist the
    player meant at the top.

    Junk acts are ranked last rather than removed — someone searching for a
    karaoke channel by name should still find it. Only `is_blocked` hides an
    artist outright.
    """
    query = (query or '').strip()
    if len(query) < 2:
        return []

    artists = _local_artists(query, limit)

    # Stand-ins built from a track's artist *name* have no Deezer ID, so they
    # cannot be pinned to an entity, carry no artwork and cannot start a
    # directed session. They are a fallback, not coverage — counting them here
    # would suppress the enrichment that turns them into real artists, and the
    # seeded catalogue's three hundred name-only acts would stay name-only
    # forever.
    real = [a for a in artists if a.deezer_id]

    if len(real) < ENRICH_BELOW:
        if real:
            # We have something to show, so the round-trip can happen after the
            # response. The next keystroke, 350 ms later, sees the new rows.
            _enrich_later(_enrich_artists, 'artists', query)
        else:
            # Nothing at all locally. This is the case the open catalogue
            # exists for — a player looking for an act we have never heard of —
            # so it is worth one live call before showing an empty list.
            fetched = _enrich_now(_enrich_artists, 'artists', query)
            if fetched:
                # Keep any name-only stand-ins alongside the real entities:
                # Deezer does not necessarily know an act we hold tracks for.
                known = {a.deezer_id for a in fetched}
                artists = fetched + [
                    a for a in artists if a.deezer_id not in known
                ]

    artists.sort(key=lambda a: (a.is_junk, -a.nb_fan))
    return artists[:limit]


def resolve_artist(name: str) -> Optional[Artist]:
    """
    The Deezer entity for an artist *name*, or None if there is no safe match.

    Goes straight to Deezer rather than through `search_artists`, which is
    tuned for a player typing: it answers from the local table and only calls
    out when the catalogue looks thin. Correct for autocomplete, useless for a
    caller whose entire purpose is to resolve one name.

    Refuses anything whose normalised name is not the one asked for. Deezer's
    artist search is fuzzy — `q=weeknd` returns a 2 101-fan namesake above the
    real one, plus a covers act called "The Retro Weeknd" — so accepting the
    top result would attach the wrong identity to a whole discography, silently
    and permanently.
    """
    wanted = normalize_artist(name)
    if not wanted:
        return None
    candidates = [a for a in _enrich_artists(name) if a.deezer_id and a.norm_name == wanted]
    if not candidates:
        return None
    # Several acts can share a name exactly; the one with the audience is the
    # one a player means.
    return max(candidates, key=lambda a: a.nb_fan)


def _enrich_artists(query: str, max_wait: Optional[float] = None) -> list[Artist]:
    """Pull Deezer's artist results for `query` into the catalogue."""
    artists = []
    for payload in _deezer(max_wait).search_artists(query, limit=25):
        artist = upsert_artist(payload)
        if artist and not artist.is_blocked:
            artists.append(artist)
    return artists


def _local_artists(query: str, limit: int) -> list[Artist]:
    """
    Artists we can name without Deezer.

    Mostly one table, since migration 0016 gave every artist with a Deezer ID a
    row and `sync_artists_from_tracks` keeps it that way.

    The second pass survives for the artists that migration *could not* reach:
    `artists` is keyed on the Deezer ID, so an act whose tracks were all seeded
    before that column existed has nowhere to live. There are still around
    three hundred of them, and dropping this would have made every one of them
    unsearchable while leaving them perfectly playable by name — the exact
    "your app doesn't have my artist" complaint this whole change is meant to
    remove.

    Rows built here are unsaved stand-ins with no Deezer ID; the client falls
    back to playing them by name. They carry no artwork: that moved to
    `artists`, and an artist we have no row for has no artwork to show.
    """
    norm = normalize_artist(query)
    found = list(
        Artist.objects.filter(
            Q(name__icontains=query) | Q(norm_name__startswith=norm),
            is_blocked=False,
        )[:limit]
    )
    if len(found) >= limit:
        return found

    known = {a.norm_name for a in found}
    rows = (
        Track.objects.filter(artist__icontains=query, deezer_artist_id__isnull=True)
        .values_list('artist', flat=True)
        .order_by('artist')
        .distinct()
    )
    for name in rows:
        if len(found) >= limit:
            break
        if normalize_artist(name) in known:
            continue
        known.add(normalize_artist(name))
        found.append(Artist(deezer_id=None, name=name, nb_fan=0))
    return found


# ── Tracks ───────────────────────────────────────────────────────────────────

def _playable_payload(info: dict) -> bool:
    """A payload with no preview is unplayable whatever else is true of it."""
    return bool(info.get('preview_url') and info.get('title') and info.get('artist'))


@transaction.atomic
def upsert_track(info: dict) -> Optional[Track]:
    """
    Write one extracted track payload through to the catalogue.

    Keyed on `deezer_id`, which is unique as of migration 0011 — one row per
    *release*, not per song.

    That distinction matters. Matching on the normalised (title, artist)
    identity instead would fold the remix, the live take and the album cut into
    a single row, and since a newer preview URL always wins, importing
    "Blinding Lights (Live)" would quietly replace the studio audio behind a
    row still titled "Blinding Lights" — a round playing a live recording while
    claiming to be the single. Releases stay separate here; collapsing them is
    the job of `matching`, which decides answers, and of `search_tracks`, which
    decides what the player sees.

    The one identity-based lookup left is for rows seeded before Deezer IDs
    were recorded: those are adopted rather than duplicated, which is how the
    original curated catalogue gains its IDs over time.
    """
    if not _playable_payload(info):
        return None

    sync_artists_from_tracks([info])
    deezer_id = info.get('deezer_id')
    track = None
    if deezer_id:
        track = Track.objects.filter(deezer_id=deezer_id).first()
        if track is None:
            # No row for this release yet. Adopt a legacy row for the same song
            # only if it has no Deezer ID of its own — otherwise this really is
            # a new release and deserves its own row.
            track = Track.objects.filter(
                norm_title=normalize_title(info['title']),
                norm_artist=normalize_artist(info['artist']),
                deezer_id__isnull=True,
            ).first()
    else:
        track = Track.objects.filter(
            norm_title=normalize_title(info['title']),
            norm_artist=normalize_artist(info['artist']),
        ).first()

    if track is None:
        try:
            return Track.objects.create(
                title=info['title'],
                artist=info['artist'],
                has_preview=True,
                cover_url=info.get('cover_url'),
                deezer_id=deezer_id,
                deezer_artist_id=info.get('deezer_artist_id'),
                release_year=info.get('release_year'),
                genre=info.get('genre'),
                rank=info.get('rank') or 0,
                is_curated=bool(info.get('is_curated')),
                last_seen_at=timezone.now(),
            )
        except IntegrityError:
            # Another worker imported the same track between the lookup and
            # the insert. Theirs is as good as ours.
            return Track.objects.filter(deezer_id=deezer_id).first()

    changed = ['last_seen_at']
    track.last_seen_at = timezone.now()
    # One-way: a track that has appeared in a chart keeps that standing even if
    # a later open-search import touches the same row.
    if info.get('is_curated') and not track.is_curated:
        track.is_curated = True
        changed.append('is_curated')
    if deezer_id and not track.deezer_id:
        track.deezer_id = deezer_id
        changed.append('deezer_id')
    if not track.has_preview:
        # `_playable_payload` already established the payload carries audio.
        track.has_preview = True
        changed.append('has_preview')
    for field in _REFRESHABLE:
        value = info.get(field)
        if not value:
            continue
        # Only ever fill a gap, to avoid churning good data on every import.
        if not getattr(track, field):
            setattr(track, field, value)
            changed.append(field)
    track.save(update_fields=set(changed))
    return track


def upsert_tracks(payloads: Iterable[dict], fallback_genre: Optional[str] = None) -> list[Track]:
    """
    Extract and persist a batch of raw Deezer track payloads.

    Goes through `bulk_upsert_tracks` rather than looping over `upsert_track`:
    a fifty-result search used to cost about a hundred sequential queries, and
    it ran on the request path of every keystroke.
    """
    deezer = DeezerService()
    infos = [
        deezer.extract_track_info(payload, fallback_genre=fallback_genre)
        for payload in payloads
    ]
    return bulk_upsert_tracks(infos)


def bulk_upsert_tracks(infos: Iterable[dict]) -> list[Track]:
    """
    Persist many extracted payloads in a handful of queries.

    Same rules as `upsert_track` — keyed on `deezer_id`, adopting ID-less
    legacy rows for the same song, and only ever filling gaps — but resolved
    set-at-a-time instead of row-at-a-time.

    Two things `bulk_create` does not do for us, both of which are silent
    corruption if forgotten: it bypasses `Model.save()`, so `norm_title` and
    `norm_artist` have to be computed here (they are what makes a guess match),
    and it bypasses `auto_now_add`, so `created_at` has to be set explicitly.
    """
    infos = [i for i in infos if i and _playable_payload(i)]
    if not infos:
        return []

    now = timezone.now()

    # Deezer can return the same track twice in one page; last one wins, which
    # matches the row-at-a-time behaviour.
    by_deezer_id: dict[int, dict] = {}
    without_id: list[dict] = []
    for info in infos:
        if info.get('deezer_id'):
            by_deezer_id[info['deezer_id']] = info
        else:
            without_id.append(info)

    existing = {
        t.deezer_id: t
        for t in Track.objects.filter(deezer_id__in=list(by_deezer_id))
    }

    # Rows seeded before Deezer IDs were recorded are adopted rather than
    # duplicated. Only rows with no ID of their own qualify: anything else is
    # genuinely a different release.
    identities = {
        (normalize_title(i['title']), normalize_artist(i['artist']))
        for did, i in by_deezer_id.items() if did not in existing
    }
    identities |= {
        (normalize_title(i['title']), normalize_artist(i['artist']))
        for i in without_id
    }
    legacy: dict[tuple[str, str], Track] = {}
    if identities:
        candidates = Track.objects.filter(
            norm_title__in=[t for t, _ in identities],
            norm_artist__in=[a for _, a in identities],
        )
        for track in candidates:
            key = (track.norm_title, track.norm_artist)
            if key not in identities:
                continue
            # An ID-less row can be adopted; one that already has an ID is a
            # different release and must be left alone.
            if track.deezer_id is None or key not in legacy:
                legacy.setdefault(key, track)

    creates: list[Track] = []
    updates: list[Track] = []
    changed_fields: set[str] = set()
    seen: list[Track] = []

    for info in list(by_deezer_id.values()) + without_id:
        deezer_id = info.get('deezer_id')
        identity = (normalize_title(info['title']), normalize_artist(info['artist']))
        track = existing.get(deezer_id) if deezer_id else None
        if track is None:
            candidate = legacy.get(identity)
            if candidate is not None and (candidate.deezer_id is None or not deezer_id):
                track = candidate

        if track is None:
            track = Track(
                title=info['title'],
                artist=info['artist'],
                norm_title=identity[0],
                norm_artist=identity[1],
                has_preview=True,
                cover_url=info.get('cover_url'),
                deezer_id=deezer_id,
                deezer_artist_id=info.get('deezer_artist_id'),
                release_year=info.get('release_year'),
                genre=info.get('genre'),
                rank=info.get('rank') or 0,
                is_curated=bool(info.get('is_curated')),
                is_variant=is_variant_title(info['title']),
                last_seen_at=now,
                created_at=now,
            )
            creates.append(track)
            # Claim the identity so a second release in the same batch does not
            # also try to adopt it.
            legacy.setdefault(identity, track)
            seen.append(track)
            continue

        track.last_seen_at = now
        changed_fields.add('last_seen_at')
        if info.get('is_curated') and not track.is_curated:
            track.is_curated = True
            changed_fields.add('is_curated')
        if deezer_id and not track.deezer_id:
            track.deezer_id = deezer_id
            changed_fields.add('deezer_id')
        if not track.has_preview:
            track.has_preview = True
            changed_fields.add('has_preview')
        for field in _REFRESHABLE:
            value = info.get(field)
            if not value:
                continue
            if not getattr(track, field):
                setattr(track, field, value)
                changed_fields.add(field)
        updates.append(track)
        seen.append(track)

    sync_artists_from_tracks(infos)

    if creates:
        # Sorted on the identity Postgres indexes, because ignore_conflicts only
        # settles who wins a collision — not the order the rows are locked in.
        # Two workers importing the same Deezer page in the orders they happened
        # to receive it each held an index tuple the other was waiting on, and
        # Postgres broke the tie by killing one with `deadlock detected`. A total
        # order every worker agrees on means the second one queues instead.
        creates.sort(key=lambda t: (t.deezer_id or 0, t.norm_title, t.norm_artist))
        # ignore_conflicts because another worker may be importing the same
        # search results right now; theirs is as good as ours.
        Track.objects.bulk_create(creates, ignore_conflicts=True, batch_size=200)
    if updates and changed_fields:
        # Same reasoning as the sort above: concurrent updates touching one row
        # set deadlock just as readily as concurrent inserts.
        updates.sort(key=lambda t: str(t.pk))
        Track.objects.bulk_update(updates, sorted(changed_fields), batch_size=200)

    return seen


# ── Quality floor (undirected picks only) ────────────────────────────────────

def playable(qs: QuerySet, directed: bool = False) -> QuerySet:
    """
    Restrict a track queryset to what is worth playing.

    `directed=True` means the player named the artist, so only the hard
    requirement applies: there has to be audio. Everything else — the rank
    floor, the follower floor, the variant and junk exclusions — is about not
    handing someone a karaoke cover when *we* did the choosing.
    """
    # Audio is resolved by Deezer track ID at play time, so a row without one
    # can never be played however much metadata it carries. Before previews
    # became ephemeral such a row could still be served from its stored URL;
    # now it would only ever produce a 503.
    qs = qs.filter(has_preview=True, deezer_id__isnull=False)
    if directed:
        return qs

    config = settings_row()
    junk_artist_ids = Artist.objects.filter(
        Q(is_junk=True) | Q(is_blocked=True)
    ).values_list('deezer_id', flat=True)

    return (
        # Variants are answers, not rounds. See Track.is_variant for why this
        # has to be a stored column rather than a title check here.
        qs.exclude(is_variant=True)
        .filter(
            # Curated: it came from a Deezer chart or editorial playlist, which
            # is a stronger popularity signal than any threshold we could set.
            Q(is_curated=True)
            # rank 0 means *unknown*, not unpopular. Every track seeded before
            # the column existed has it, and those came from a hand-picked list
            # of 206 artists — exactly the material the floor is meant to
            # protect. Reading 0 as "below the floor" would empty the pool on
            # the day this deploys.
            | Q(rank=0)
            | Q(rank__gte=config.min_track_rank)
        )
        .exclude(deezer_artist_id__in=junk_artist_ids)
    )


#: Why a payload was turned away, in the order the floor tests them. Kept as
#: stable slugs rather than prose because `crawl_artists --floor-report` groups
#: on them and a report is read by comparing runs.
REJECT_NO_AUDIO = 'no-audio'
REJECT_JUNK_ARTIST = 'junk-artist'
REJECT_VARIANT = 'variant'
REJECT_RANK = 'rank-below-floor'
REJECT_ARTIST_FANS = 'artist-below-fan-floor'


def payload_rejection(
    info: dict,
    artist: Optional[Artist],
    directed: bool,
    curated: bool = False,
) -> Optional[str]:
    """
    Why the floor would turn this payload away, or None if it passes.

    The reason is the whole point: a bare yes/no cannot tell you whether a run
    is being trimmed of karaoke covers or of genuinely popular tracks whose
    artist simply has few Deezer followers, and those call for opposite
    decisions. `is_playable_payload` is the boolean view of this function —
    one implementation, so a report can never drift from the filter it describes.

    `curated` means the payload came from a Deezer chart or editorial playlist.
    Those skip the popularity floors, because the source already did that job —
    and did it better. Deezer's follower counts track its own European
    listenership, so a global floor quietly guts every category outside that
    market: at 50 000 fans, "Top J-Pop" keeps 7 tracks of 61 (median follower
    count of the rejects: 7 879) and Bollywood keeps 15 of 100. Those are hits,
    not junk.

    What still applies everywhere: there has to be audio, it must not be a
    karaoke or tribute act, and it must not be an alternate release.
    """
    if not _playable_payload(info):
        return REJECT_NO_AUDIO
    if directed:
        return None

    if is_junk_artist(info.get('artist', '')):
        return REJECT_JUNK_ARTIST
    if is_variant_title(info.get('title', '')):
        return REJECT_VARIANT
    if curated:
        return None

    config = settings_row()
    if (info.get('rank') or 0) < config.min_track_rank:
        return REJECT_RANK
    if artist is not None and artist.nb_fan and artist.nb_fan < config.min_artist_fans:
        return REJECT_ARTIST_FANS
    return None


def is_playable_payload(
    info: dict,
    artist: Optional[Artist],
    directed: bool,
    curated: bool = False,
) -> bool:
    """Whether the floor would store this payload. See `payload_rejection`."""
    return payload_rejection(info, artist, directed, curated) is None


# ── Directed play: one artist's catalogue ────────────────────────────────────

def ensure_artist_tracks(deezer_artist_id: int, minimum: int = 30) -> list[Track]:
    """
    Make sure the catalogue holds enough of one artist to play a session.

    Called when a player picks an artist. Pulls the top 50 first — enough for
    almost every session — and only walks the albums when that comes up short,
    because album paging costs one Deezer request per album.

    No popularity floor is applied anywhere in here: the player asked for this
    artist by ID.
    """
    config = settings_row()
    artist = Artist.objects.filter(deezer_id=deezer_artist_id).first()
    deezer = DeezerService()

    if artist is None:
        payload = deezer.get_artist(deezer_artist_id)
        if payload:
            artist = upsert_artist(payload)

    fresh = (
        artist is not None
        and artist.top_refreshed_at is not None
        and timezone.now() - artist.top_refreshed_at
        < timedelta(days=config.artist_top_ttl_days)
    )

    existing = list(playable(
        Track.objects.filter(deezer_artist_id=deezer_artist_id), directed=True,
    ))
    if fresh and len(existing) >= minimum:
        return existing

    picture = artist.picture_url if artist else None
    imported = _import_artist_top(deezer, deezer_artist_id, picture)

    if len(imported) < minimum:
        imported = _import_artist_albums(
            deezer, deezer_artist_id, picture, wanted=minimum, already=imported,
        )

    if artist is not None:
        artist.top_refreshed_at = timezone.now()
        artist.save(update_fields=['top_refreshed_at'])

    return list(playable(
        Track.objects.filter(deezer_artist_id=deezer_artist_id), directed=True,
    ))


def _import_artist_top(deezer: DeezerService, artist_id: int, picture: Optional[str]) -> list[Track]:
    payloads = deezer.get_artist_top_tracks(artist_id, limit=50)
    return _persist_artist_payloads(deezer, payloads, artist_id, picture)


def _import_artist_albums(
    deezer: DeezerService,
    artist_id: int,
    picture: Optional[str],
    wanted: int,
    already: list[Track],
) -> list[Track]:
    """Walk the discography until `wanted` playable tracks exist, or albums run out."""
    collected = list(already)
    for album in deezer.get_artist_albums(artist_id, limit=25):
        if len(collected) >= wanted:
            break
        album_id = album.get('id')
        if not album_id:
            continue
        payloads = deezer.get_album_tracks(album_id, limit=50)
        # Album track payloads carry no album object, so the cover has to be
        # grafted on from the album we are walking or the round loses its art.
        cover = album.get('cover_xl') or album.get('cover_big') or album.get('cover_medium')
        for payload in payloads:
            payload.setdefault('album', {})
            if cover:
                payload['album'].setdefault('cover_xl', cover)
        collected.extend(_persist_artist_payloads(deezer, payloads, artist_id, picture))
    return collected


def _persist_artist_payloads(
    deezer: DeezerService,
    payloads: list[dict],
    artist_id: int,
    picture: Optional[str],
) -> list[Track]:
    infos = []
    for payload in payloads:
        info = deezer.extract_track_info(payload)
        # Album and top endpoints sometimes credit a featured artist as the
        # main one; pin the entity the player actually chose so the session
        # filter still finds these rows.
        info['deezer_artist_id'] = info.get('deezer_artist_id') or artist_id
        # Album track payloads carry an artist object with an id and a name but
        # no picture, so the artwork has to come from the artist we are walking
        # or their row never gets one. Only for rows that are actually about
        # them: a feature credited on one of these tracks is a different entity,
        # and `sync_artists_from_tracks` would create it wearing the walked
        # artist's face. That is how one photo ended up on fifteen artists.
        if (
            picture
            and info['deezer_artist_id'] == artist_id
            and not info.get('artist_picture_url')
        ):
            info['artist_picture_url'] = picture
        infos.append(info)
    return bulk_upsert_tracks(infos)


# ── Guess autocomplete ───────────────────────────────────────────────────────

MAX_ARTISTS_PER_TITLE = 3


# A search box query is a handful of words; past that it is noise, and every
# extra token is another LIKE over the table.
MAX_QUERY_TOKENS = 6


def _query_filter(query: str) -> Optional[Q]:
    """
    Match a query against title *and* artist, one word at a time.

    Two things this has to get right, both of which the plain
    `title__icontains=query` it replaces got wrong.

    Accents: the stored `norm_*` keys are folded (`ROSALÍA` → `rosalia`), so a
    raw LIKE on `artist` misses a player typing `rosalia` — and misses
    `Rosalía` too, because SQLite's LIKE only case-folds ASCII. Folding the
    query the same way is what makes an artist search work at all.

    Word order: `rosalia despecha` has to find the song, so each word matches
    independently and against either field. The raw columns stay in the
    alternatives because normalisation eats words a searcher may well type —
    the leading `The` of `The Weeknd` is stripped from `norm_artist`, and
    `(Live)` never reaches `norm_title`.
    """
    tokens = normalize_query(query).split()[:MAX_QUERY_TOKENS]
    if not tokens:
        return None
    combined = Q()
    for token in tokens:
        combined &= (
            Q(norm_title__contains=token)
            | Q(norm_artist__contains=token)
            | Q(title__icontains=token)
            | Q(artist__icontains=token)
        )
    return combined


def search_tracks(query: str, limit: int = 30) -> list[Track]:
    """
    Track autocomplete over the whole of Deezer, one row per *song*.

    The deduplication is the point. Searching `blinding lights` returns the
    album cut, the single, a live take and three remixes; a dropdown listing
    all six is worse than useless, because picking the "wrong" one used to cost
    the player the round. Collapsing on the normalised identity leaves one row,
    and `matching.answer_matches` accepts whichever release is actually
    playing.

    Ordering is by Deezer rank, which is a decent proxy for "the version people
    mean" once the variants are already collapsed away.
    """
    query = (query or '').strip()
    if len(query) < 2:
        return []

    matches = _query_filter(query)
    if matches is None:
        return []

    results = _dedupe(Track.objects.filter(matches).order_by('-rank')[:150], limit)

    if len(results) < ENRICH_BELOW:
        if results:
            _enrich_later(_enrich_tracks, 'tracks', query)
        else:
            if _enrich_now(_enrich_tracks, 'tracks', query) is not None:
                # Re-read rather than use the imported rows directly: the
                # dedup and ranking below have to see the whole catalogue's
                # releases of a song, not just the ones this call happened to
                # return.
                results = _dedupe(
                    Track.objects.filter(matches).order_by('-rank')[:150], limit,
                )
            if not results:
                _record_miss(query)

    return results


def _enrich_tracks(query: str, max_wait: Optional[float] = None) -> list[Track]:
    """Pull Deezer's track results for `query` into the catalogue."""
    payloads = _deezer(max_wait).search_track(query, limit=50).get('data', [])
    return upsert_tracks(payloads) if payloads else []


def _deezer(max_wait: Optional[float] = None) -> DeezerService:
    """A client whose patience matches whether anyone is waiting on it."""
    if max_wait is None:
        return DeezerService()
    return DeezerService(http=DeezerHttp(max_wait=max_wait))


def _dedupe(local: Iterable[Track], limit: int) -> list[Track]:
    """
    Collapse a result set to one row per song, best release first.

    Split out of `search_tracks` because it now runs twice: once on what the
    catalogue already held, and again if a live enrichment filled it in.
    """
    local = list(local)

    artist_ids = {t.deezer_artist_id for t in local if t.deezer_artist_id}
    artists = {
        a.deezer_id: a
        for a in Artist.objects.filter(deezer_id__in=artist_ids)
    }

    seen: set[tuple[str, str]] = set()
    per_title: dict[str, int] = {}
    unique: list[Track] = []
    for track in sorted(local, key=lambda t: -_search_score(t, artists)):
        key = (track.norm_title, track.norm_artist)
        if key in seen:
            continue
        # Cap how many acts can share one title. Popular songs are covered
        # dozens of times over: unfiltered, "blinding lights" fills all forty
        # rows with the same song by forty different unknown singers, and the
        # list stops being able to show anything else. Three leaves room for
        # the titles several famous songs genuinely share — Hello by Adele, by
        # Lionel Richie, by Martin Solveig — while cutting the covers off.
        if per_title.get(track.norm_title, 0) >= MAX_ARTISTS_PER_TITLE:
            continue
        seen.add(key)
        per_title[track.norm_title] = per_title.get(track.norm_title, 0) + 1
        unique.append(track)
        if len(unique) >= limit:
            break
    return unique


def _search_score(track: Track, artists: dict) -> float:
    """
    How high a result should sit in the guess list.

    Track rank alone is not enough. Searching "blinding lights" returns The
    Weeknd's original at rank 984 833 — and then covers by unknown singers at
    633 257, 594 628 and 591 569, which is close enough that they crowd the
    list right under the answer. That matters more than it looks: a cover by a
    different artist is judged *wrong*, so a player who identified the song
    correctly can still lose a life by picking the wrong row.

    So a known follower count nudges a result up, on a log scale — enough to
    separate a 14-million-fan act from an unknown one at a similar rank, but
    not enough to bury a genuinely obscure artist the player may be looking
    for. Artists we hold no fan count for keep their raw rank and compete on
    that alone.

    Karaoke and tribute acts sort last outright. They are still reachable, for
    the player who really did mean to pick one.
    """
    artist = artists.get(track.deezer_artist_id)
    if artist is not None and (artist.is_junk or artist.is_blocked):
        return -1.0

    score = float(track.rank)
    if artist is not None and artist.nb_fan:
        score *= 1.0 + math.log10(1 + artist.nb_fan) / 10.0
    return score


# ── Answer checking ──────────────────────────────────────────────────────────

def check_guess(
    answer: Track,
    *,
    guess_track_id: Optional[str] = None,
    guess_deezer_id: Optional[int] = None,
    guess_title: str = '',
    guess_artist: str = '',
) -> bool:
    """
    Decide whether a guess names the song being played.

    Accepts whichever handle the caller has: our own track UUID (what the
    autocomplete returns), a Deezer track ID, or a bare title/artist pair. All
    three collapse to the same normalised comparison, so the answer is judged
    identically from the solo endpoint, the duel socket and the tests.

    No quality rule applies here: a live cut or a remix is a poor snippet but
    a perfectly correct answer. The artist, however, still has to match — see
    `matching.answer_matches`.
    """
    guess = None
    if guess_track_id:
        guess = Track.objects.filter(id=guess_track_id).first()
    if guess is None and guess_deezer_id:
        guess = Track.objects.filter(deezer_id=guess_deezer_id).first()

    if guess is not None:
        return answer_matches(
            answer_deezer_id=answer.deezer_id,
            answer_norm_title=answer.norm_title,
            answer_norm_artist=answer.norm_artist,
            answer_artist_deezer_id=answer.deezer_artist_id,
            guess_deezer_id=guess.deezer_id,
            guess_norm_title=guess.norm_title,
            guess_norm_artist=guess.norm_artist,
            guess_artist_deezer_id=guess.deezer_artist_id,
        )

    # Nothing stored under that handle — fall back to the literal strings the
    # client sent. This keeps a guess valid when the player picked a Deezer
    # result that failed to persist (no preview, say).
    if not guess_title:
        return False
    return answer_matches(
        answer_deezer_id=answer.deezer_id,
        answer_norm_title=answer.norm_title,
        answer_norm_artist=answer.norm_artist,
        answer_artist_deezer_id=answer.deezer_artist_id,
        guess_deezer_id=guess_deezer_id,
        guess_norm_title=normalize_title(guess_title),
        guess_norm_artist=normalize_artist(guess_artist),
        guess_artist_deezer_id=None,
    )


def song_identity(title: str, artist: str) -> tuple[str, str]:
    """Re-exported so callers do not reach into `matching` for the common case."""
    return song_key(title, artist)
