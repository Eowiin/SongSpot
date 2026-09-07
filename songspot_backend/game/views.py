import random
import uuid
from datetime import timedelta

from django.db import transaction
from django.db.models import Count, Q
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from songspot.api_errors import ErrorCode, error_response
from songspot.throttling import GameSearchThrottle

from .models import (
    Artist, Track, GameScore, UserBest, FavouriteArtist,
    Playlist, PlaylistTrack,
    DuelMatch, UserElo,
    CATEGORY_CHOICES,
)
from .serializers import (
    ArtistSerializer,
    GuessSerializer,
    TrackAnswerSerializer,
    TrackRoundSerializer,
    TrackSerializer,
    TrackSearchSerializer,
    GameScoreSubmitSerializer,
    GameScoreSerializer,
    UserBestSerializer,
    LeaderboardEntrySerializer,
    MigrateGuestStatsSerializer,
    DuelMatchSerializer,
    UserEloSerializer,
    DuelLeaderboardEntrySerializer,
)
from .services import catalog, previews, rounds

# A round is played by one client version or the other. v1 judges the guess
# locally and therefore needs the answer in the payload; v2 posts to /guess/
# and gets the answer back only once it has committed to one. Both are served
# because a store rollout takes days, and every already-installed app is v1
# the moment this deploys.
API_V2 = 2

# The client sends every track it has already heard. Left unbounded that list
# grows for the whole session and eventually blows the URL length; the tail is
# what actually matters for avoiding repeats.
MAX_EXCLUDE = 200


def _client_version(request) -> int:
    try:
        return int(request.query_params.get('v', 1))
    except (TypeError, ValueError):
        return 1

class PlaylistListView(APIView):
    """Return all playlists that have at least one track."""
    permission_classes = [AllowAny]

    def get(self, request):
        playlists = (
            Playlist.objects
            .annotate(num_tracks=Count('playlist_tracks'))
            .filter(num_tracks__gt=0)
            .order_by('name')
        )
        result = [
            {
                'id': str(p.id),
                'name': p.name,
                'category': p.category,
                'track_count': p.num_tracks,
            }
            for p in playlists
        ]
        return Response(result)


class NextSongView(APIView):
    """
    Return a track to play for the current session.

    Query params:
      playlist   — playlist UUID (a category)
      artist_id  — Deezer artist ID; the player picked this artist
      artist     — artist *name*; the v1 way of saying the same thing
      exclude    — comma-separated track UUIDs already heard this session
      v          — client API version (2 withholds the answer, see API_V2)

    Naming an artist makes the pick *directed*, which switches off the quality
    floor entirely: the player asked for this act, so their 200-fan favourite
    is as valid as a chart topper. Categories and mixed play stay filtered,
    because there the game is choosing and the song has to be recognisable.
    """
    permission_classes = [AllowAny]
    throttle_classes = [GameSearchThrottle]

    def get(self, request):
        playlist_id = request.query_params.get('playlist', '').strip()
        artist_name = request.query_params.get('artist', '').strip()
        artist_id_raw = request.query_params.get('artist_id', '').strip()
        exclude_raw = request.query_params.get('exclude', '')
        exclude_ids = [e.strip() for e in exclude_raw.split(',') if e.strip()][-MAX_EXCLUDE:]

        artist_deezer_id = None
        if artist_id_raw:
            try:
                artist_deezer_id = int(artist_id_raw)
            except ValueError:
                return Response(
                    {'detail': 'artist_id must be a Deezer artist ID.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
        elif artist_name:
            # v1 clients only know the name. Resolving it to an entity here is
            # what lets an app that has not been updated yet still reach the
            # open catalogue.
            matches = catalog.search_artists(artist_name, limit=1)
            if matches:
                artist_deezer_id = matches[0].deezer_id

        directed = artist_deezer_id is not None or bool(artist_name)
        pool_size = None

        # Which Deezer containers can supply this round's audio, cheapest
        # first. A container hit is free once any player has warmed it; see
        # services/previews for why previews cannot come from the database.
        containers: list[tuple[str, int]] = []

        if artist_deezer_id is not None:
            # Pull enough of this artist into the catalogue to play a session.
            catalog.ensure_artist_tracks(artist_deezer_id)
            qs = Track.objects.filter(deezer_artist_id=artist_deezer_id)
            pool_size = catalog.playable(qs, directed=True).count()
            containers = [('artist', artist_deezer_id)]
            if pool_size == 0 and artist_name:
                # The name resolved to a Deezer artist we hold nothing for —
                # Deezer may be unreachable, or the match may have been wrong.
                # Playing what we do have under that name beats telling the
                # player their artist does not exist.
                qs = Track.objects.filter(artist__icontains=artist_name)
                pool_size = None
        elif playlist_id:
            track_ids = PlaylistTrack.objects.filter(
                playlist_id=playlist_id
            ).values_list('track_id', flat=True)
            qs = Track.objects.filter(id__in=track_ids)
            playlist = Playlist.objects.filter(id=playlist_id).first()
            if playlist is not None:
                containers = previews.playlist_containers(playlist)
        elif artist_name:
            qs = Track.objects.filter(artist__icontains=artist_name)
        else:
            qs = Track.objects.all()

        qs = catalog.playable(qs, directed=directed)
        if exclude_ids:
            qs = qs.exclude(id__in=exclude_ids)

        track, preview_url = _pick_with_audio(qs, containers)
        if track is None:
            return Response(
                {'detail': 'No tracks available.', 'pool_size': pool_size},
                status=status.HTTP_404_NOT_FOUND,
            )
        if preview_url is None:
            # The pool is fine; Deezer is not. Distinct from a 404 on purpose —
            # "we have no songs for you" and "we cannot reach the audio right
            # now" call for different things from the client, and conflating
            # them once had players reinstalling the app over an outage.
            return error_response(
                code=ErrorCode.AUDIO_UNAVAILABLE,
                message='Audio temporarily unavailable.',
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        # Set in memory only, and there is nowhere to persist it to: `tracks`
        # holds `has_preview`, not the URL. See services/previews.
        track.preview_url = preview_url

        if _client_version(request) >= API_V2:
            payload = TrackRoundSerializer(track).data
            payload['round_token'] = rounds.issue(track.id, directed=directed)
        else:
            payload = TrackSerializer(track).data
        if pool_size is not None:
            payload['pool_size'] = pool_size
        return Response(payload)


# How many candidates a round tries before giving up. Each miss can cost one
# Deezer call, so this is a budget as much as a retry count: a pool that misses
# three times running has a real problem, and a 404 the client can retry beats
# walking the table at one API call per row.
PREVIEW_ATTEMPTS = 3

# Size of the random block candidates are drawn from. Bounded so the read stays
# an indexed range scan instead of a sort over the whole catalogue.
CANDIDATE_BLOCK = 500


def _random_candidates(qs, limit: int) -> list:
    """
    Up to `limit` tracks drawn at random, without counting the table.

    This replaces `qs[random.randint(0, qs.count() - 1)]`, which cost a COUNT
    plus a random OFFSET — and an OFFSET walks every row it skips. Unnoticeable
    over four thousand tracks, which is exactly why it had to go before the
    catalogue grows to a million.

    Primary keys are UUID4 and so uniformly distributed: seeking to a random
    one and reading forward lands on a random block in a single indexed scan.
    Rows that follow a large gap in the keyspace are slightly likelier to come
    up; for picking a song to play, that bias is not worth a second query.
    """
    marker = uuid.uuid4()
    ids = list(
        qs.filter(id__gte=marker).order_by('id')
          .values_list('id', flat=True)[:CANDIDATE_BLOCK]
    )
    if len(ids) < CANDIDATE_BLOCK:
        # Ran off the end of the keyspace — wrap around to the start.
        ids += list(
            qs.filter(id__lt=marker).order_by('id')
              .values_list('id', flat=True)[:CANDIDATE_BLOCK - len(ids)]
        )
    if not ids:
        return []
    picks = random.sample(ids, min(limit, len(ids)))
    by_id = Track.objects.in_bulk(picks)
    return [by_id[i] for i in picks if i in by_id]


def _pick_with_audio(qs, containers):
    """
    A track from `qs` and a preview URL that will actually play.

    Preview URLs are signed with a fifteen-minute expiry, so there is nothing
    stored to fall back on — the URL has to be resolved now, and a track whose
    audio will not resolve is simply not playable this round. The next
    candidate is tried rather than serving the player silence.

    Three return shapes, which the caller turns into three different answers:

    * `(track, url)` — a playable round.
    * `(None, None)` — the pool itself is empty. A 404.
    * `(track, None)` — the pool is fine but Deezer is not. A 503.
    """
    candidates = _random_candidates(qs, PREVIEW_ATTEMPTS)
    if not candidates:
        return None, None
    for candidate in candidates:
        track = _canonical(candidate)
        url = previews.resolve(track, containers)
        if url:
            return track, url
    return candidates[0], None


def _canonical(track: Track) -> Track:
    """
    Swap a track for the best-known release of the same song.

    Several rows can describe one song — the album cut, the single, a remaster.
    Serving the highest-ranked of them keeps the round consistent with the
    autocomplete, which collapses the same group down to that same row. It also
    keeps v1 clients, which still compare UUIDs, right far more often than they
    were: today they are marked wrong whenever the round lands on a row other
    than the one search offers.
    """
    if not track.norm_title:
        return track
    best = (
        Track.objects
        .filter(norm_title=track.norm_title, norm_artist=track.norm_artist)
        .filter(has_preview=True)
        .order_by('-rank')
        .first()
    )
    return best or track


class GuessView(APIView):
    """
    Judge a guess against an open round.

    This is the endpoint the open catalogue made necessary. The app used to
    decide for itself, by comparing the UUID it picked against the UUID it was
    handed — which is only correct when every song has exactly one row. Deezer
    ships one row per *release*, so `Blinding Lights` alone has six, and the
    old rule marks a player wrong for naming the right song off the wrong one.

    Sending no guess means the player gave up, and returns the answer.
    """
    permission_classes = [AllowAny]
    throttle_classes = [GameSearchThrottle]

    def post(self, request):
        serializer = GuessSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        try:
            payload = rounds.resolve(data['round_token'])
        except rounds.InvalidRoundToken as exc:
            return Response(
                {'detail': f'Invalid round token ({exc}).'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        answer = Track.objects.filter(id=payload['t']).first()
        if answer is None:
            return Response({'detail': 'Round not found.'}, status=status.HTTP_404_NOT_FOUND)

        gave_up = not (
            data.get('guess_track_id')
            or data.get('guess_deezer_id')
            or data.get('guess_title')
        )
        correct = False if gave_up else catalog.check_guess(
            answer,
            guess_track_id=data.get('guess_track_id'),
            guess_deezer_id=data.get('guess_deezer_id'),
            guess_title=data.get('guess_title', ''),
            guess_artist=data.get('guess_artist', ''),
        )

        return Response({
            'correct': correct,
            'gave_up': gave_up,
            'answer': TrackAnswerSerializer(answer).data,
        })


class ArtistListView(APIView):
    """
    Artist autocomplete, over the whole of Deezer.

    This used to be `DISTINCT artist` over the local tracks table, which is why
    players kept reporting missing artists: an artist absent from the 206-name
    seed list simply did not exist. It now searches Deezer and ranks on
    follower count, because Deezer's own ordering is unusable for picking — a
    search for "weeknd" returns a 2 101-fan namesake above the real one.
    """
    permission_classes = [AllowAny]
    throttle_classes = [GameSearchThrottle]

    def get(self, request):
        q = request.query_params.get('q', '').strip()
        if len(q) < 2:
            return Response([])
        artists = catalog.search_artists(q, limit=30)
        return Response(ArtistSerializer(artists, many=True).data)


class ArtistTrendingView(APIView):
    """
    Artists most frequently chosen for play sessions over the last 30 days.
    Aggregated from GameScore.artist_filter.
    """
    permission_classes = [AllowAny]

    def get(self, request):
        since = timezone.now() - timedelta(days=30)
        rows = (
            GameScore.objects
            .filter(played_at__gte=since)
            .exclude(artist_filter='')
            .values('artist_filter')
            .annotate(play_count=Count('id'))
            .order_by('-play_count')[:20]
        )
        artist_names = [r['artist_filter'] for r in rows]
        return Response(_artist_cards(artist_names))


def _artist_cards(names: list[str]) -> list[dict]:
    """
    Build the {name, picture_url, deezer_id} rows the select screen shows.

    Artist art comes from the `artists` table first, since that is keyed on the
    Deezer entity and is filled for every artist ever searched. The tracks
    table is the fallback for names recorded before the catalogue opened, when
    the picture only ever lived on a track row.
    """
    from .services.matching import normalize_artist

    by_norm = {normalize_artist(n): n for n in names}
    cards = {n: {'name': n, 'picture_url': None, 'deezer_id': None} for n in names}

    for artist in Artist.objects.filter(norm_name__in=by_norm.keys()).order_by('-nb_fan'):
        name = by_norm.get(artist.norm_name)
        if name and cards[name]['deezer_id'] is None:
            cards[name]['picture_url'] = artist.picture_url
            cards[name]['deezer_id'] = artist.deezer_id

    # A name that matched no artist row directly may still be reachable
    # through a track that credits it: the stored name and the artist entity's
    # own name are not always spelled the same. Artwork itself lives only on
    # `artists` since migration 0016.
    missing = [n for n, card in cards.items() if card['deezer_id'] is None]
    if missing:
        by_artist_id = {}
        for row in (
            Track.objects
            .filter(artist__in=missing, deezer_artist_id__isnull=False)
            .values('artist', 'deezer_artist_id')
        ):
            by_artist_id.setdefault(row['deezer_artist_id'], row['artist'])
        for artist in Artist.objects.filter(deezer_id__in=by_artist_id):
            card = cards.get(by_artist_id[artist.deezer_id])
            if card and card['deezer_id'] is None:
                card['picture_url'] = card['picture_url'] or artist.picture_url
                card['deezer_id'] = artist.deezer_id

    return [cards[n] for n in names]


class FavouriteArtistView(APIView):
    """List and add favourite artists for the current user."""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        rows = list(
            FavouriteArtist.objects
            .filter(user=request.user)
            .values_list('artist_name', 'artist_deezer_id')
        )
        cards = _artist_cards([name for name, _ in rows])
        # A favourite saved with an explicit Deezer ID wins over the one
        # inferred from the name.
        stored = {name: deezer_id for name, deezer_id in rows if deezer_id}
        for card in cards:
            if card['name'] in stored:
                card['deezer_id'] = stored[card['name']]
        return Response(cards)

    def post(self, request):
        artist_name = (request.data.get('artist_name') or '').strip()
        if not artist_name:
            return Response({'detail': 'artist_name is required.'}, status=status.HTTP_400_BAD_REQUEST)

        deezer_id = request.data.get('artist_deezer_id')
        try:
            deezer_id = int(deezer_id) if deezer_id else None
        except (TypeError, ValueError):
            deezer_id = None

        favourite, _ = FavouriteArtist.objects.get_or_create(
            user=request.user, artist_name=artist_name,
        )
        # Backfill the entity on a favourite saved before the app sent one, so
        # older rows stop depending on name resolution over time.
        if deezer_id and favourite.artist_deezer_id != deezer_id:
            favourite.artist_deezer_id = deezer_id
            favourite.save(update_fields=['artist_deezer_id'])

        return Response(
            {'artist_name': artist_name, 'artist_deezer_id': favourite.artist_deezer_id},
            status=status.HTTP_201_CREATED,
        )


class FavouriteArtistDetailView(APIView):
    """Remove a single favourite artist."""
    permission_classes = [IsAuthenticated]

    def delete(self, request, artist_name):
        FavouriteArtist.objects.filter(user=request.user, artist_name=artist_name).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class SearchTracksView(APIView):
    """
    Autocomplete for the guess box, over the whole of Deezer.

    Results are collapsed to one row per *song*. Without that, searching
    "blinding lights" offers the album cut, the single, a live take and three
    remixes, and the player has to pick the right release to be counted right —
    which is exactly the trap this work removes.
    """
    permission_classes = [AllowAny]
    throttle_classes = [GameSearchThrottle]

    def get(self, request):
        q = request.query_params.get('q', '').strip()
        if len(q) < 2:
            return Response([])
        tracks = catalog.search_tracks(q, limit=40)
        return Response(TrackSearchSerializer(tracks, many=True).data)


class TrackRefreshPreviewView(APIView):
    """
    Re-resolve a track's preview URL.

    The client calls this when playback fails, which after the fifteen-minute
    token expiry means "the URL I was given has aged out". Resolution goes
    through the artist pool first, so a burst of players hitting this on the
    same artist costs one Deezer call between them rather than one each.
    """
    permission_classes = [AllowAny]

    def post(self, request, track_id):
        try:
            track = Track.objects.get(id=track_id)
        except Track.DoesNotExist:
            return Response({'detail': 'Not found.'}, status=status.HTTP_404_NOT_FOUND)
        url = previews.resolve(track)
        if url is None:
            return error_response(
                code=ErrorCode.AUDIO_UNAVAILABLE,
                message='Audio temporarily unavailable.',
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        return Response({'preview_url': url})


class SubmitScoreView(APIView):
    """Submit a completed session score. Creates GameScore and updates UserBest."""
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = GameScoreSubmitSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        session_uuid = data.get('session_uuid')
        is_partial = data.get('is_partial', False)
        score_fields = {
            'genre': data.get('genre') or None,
            'artist_filter': data.get('artist_filter', ''),
            'difficulty': data.get('difficulty', 'medium'),
            'songs_played': data['songs_played'],
            'songs_correct': data['songs_correct'],
            'best_streak': data['best_streak'],
            'total_score': data['total_score'],
            'is_partial': is_partial,
        }

        with transaction.atomic():
            if session_uuid:
                score, _ = GameScore.objects.update_or_create(
                    user=request.user,
                    session_uuid=session_uuid,
                    defaults=score_fields,
                )
            else:
                score = GameScore.objects.create(user=request.user, **score_fields)

            if not is_partial:
                best, _ = UserBest.objects.select_for_update().get_or_create(user=request.user)
                best.update_from_score(score)

        return Response(GameScoreSerializer(score).data, status=status.HTTP_201_CREATED)


class UserStatsView(APIView):
    """Personal bests and aggregate stats for the current user."""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        best, _ = UserBest.objects.get_or_create(user=request.user)
        return Response(UserBestSerializer(best).data)


class LeaderboardView(APIView):
    """
    Global leaderboard of top scores.

    Query params:
      genre     — genre key to filter (omit for overall)
      timeframe — 'daily' | 'weekly' | 'alltime' (default: daily)
      limit     — max entries (default 50, max 100)
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        timeframe = request.query_params.get('timeframe', 'daily')
        genre = request.query_params.get('genre', '').strip()
        try:
            limit = min(int(request.query_params.get('limit', 50)), 100)
        except (ValueError, TypeError):
            limit = 50

        now = timezone.now()
        if timeframe == 'daily':
            since = now - timedelta(days=1)
        elif timeframe == 'weekly':
            since = now - timedelta(weeks=1)
        else:
            since = None

        qs = GameScore.objects.select_related('user').order_by('-total_score')

        if since:
            qs = qs.filter(played_at__gte=since)
        if genre:
            qs = qs.filter(genre=genre)

        return Response(LeaderboardEntrySerializer(qs[:limit], many=True).data)


class MigrateGuestStatsView(APIView):
    """Merge guest-accumulated local stats into the authenticated user's UserBest."""
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = MigrateGuestStatsSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        if data['songs_played'] == 0:
            return Response({'status': 'nothing_to_migrate'})

        with transaction.atomic():
            best, _ = UserBest.objects.select_for_update().get_or_create(user=request.user)
            best.best_score_overall = max(best.best_score_overall, data['best_score'])
            best.best_streak_overall = max(best.best_streak_overall, data['best_streak'])
            best.total_songs_played += data['songs_played']
            best.total_songs_correct += data['songs_correct']
            best.save()

        return Response({'status': 'migrated'})


# ── Duel views ────────────────────────────────────────────────────────────────

class DuelMatchDetailView(APIView):
    """Return full match state (used for reconnection after app restart)."""
    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        try:
            match = DuelMatch.objects.prefetch_related('rounds__track').get(id=pk)
        except DuelMatch.DoesNotExist:
            return Response({'detail': 'Not found.'}, status=status.HTTP_404_NOT_FOUND)
        if not match.is_player(request.user):
            return Response({'detail': 'Forbidden.'}, status=status.HTTP_403_FORBIDDEN)
        return Response(DuelMatchSerializer(match).data)


class DuelHistoryView(APIView):
    """Paginated list of completed duels for the current user."""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        limit = min(int(request.query_params.get('limit', 20)), 50)
        qs = (
            DuelMatch.objects
            .filter(
                Q(player1=request.user) | Q(player2=request.user),
                status='completed',
            )
            .select_related('player1', 'player2', 'playlist')
            .prefetch_related('rounds__track')
            .order_by('-updated_at')[:limit]
        )
        return Response(DuelMatchSerializer(qs, many=True).data)


class DuelEloView(APIView):
    """Current user's ELO and global rank."""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        elo_obj, _ = UserElo.objects.get_or_create(user=request.user, defaults={'elo': 1000})
        return Response(UserEloSerializer(elo_obj).data)


class DuelLeaderboardView(APIView):
    """Top players ranked by ELO."""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        limit = min(int(request.query_params.get('limit', 50)), 100)
        top = list(
            UserElo.objects
            .select_related('user')
            .order_by('-elo')[:limit]
        )
        ranks = {entry.user_id: idx + 1 for idx, entry in enumerate(top)}
        return Response(
            DuelLeaderboardEntrySerializer(top, many=True, context={'ranks': ranks}).data
        )
