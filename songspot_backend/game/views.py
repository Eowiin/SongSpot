from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from datetime import timedelta
from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django.conf import settings
from django.db import IntegrityError, transaction
from django.db.models import Q, Case, When, Value, IntegerField
from django.shortcuts import get_object_or_404
from django.utils import timezone
import logging
import random

logger = logging.getLogger(__name__)


from .models import (
    Track, SongPack, Room, RoomUser, RoomPack,
    DailySong, PackTrack, PackDailyTrack, PackBundleSession, PackBundleAttempt,
    DailyGameSession, GuessAttempt, RoomMessage, PackBundleMessage, PackBundleStemJob,
    DAILY_MODE_MIX, DAILY_MODE_GENRE, DAILY_MODE_DECADE, DAILY_MODE_HARDCORE,
    RoomDailyModeState, RoomDailyModeContribution,
)
from .daily_modes import (
    active_game_date,
    active_game_window,
    daily_mode_cost,
    daily_mode_label,
    daily_mode_subtitle,
    daily_mode_unlock_days,
    enabled_daily_modes,
    is_daily_mode_accessible,
    is_daily_mode_enabled,
    is_daily_mode_free,
    serialize_room_daily_modes,
    supported_daily_modes,
)
from .serializers import (
    TrackSerializer,
    SongPackListSerializer,
    SongPackDetailSerializer,
    RoomSerializer,
    RoomCreateSerializer,
    RoomRenameSerializer,
    RoomDailyModeContributionSerializer,
    JoinRoomSerializer,
    GameSessionSerializer,
    SubmitGuessSerializer,
    DailyGameRetrySerializer,
    RoomMessageSerializer,
    PackBundleMessageSerializer,
    PostMessageSerializer,
    GameHistoryEntrySerializer,
    PackBundleSessionSerializer,
    PackBundleGuessSerializer,
)
from .tasks import generate_pack_stems_task
from songspot.throttling import GuessRateThrottle, MessageRateThrottle
from songspot.api_errors import error_response, ErrorCode

# Scoring constants
SNIPPET_POINTS = {
    1: 6,  # Guessed on 0.2s snippet
    2: 5,  # Guessed on 0.5s snippet
    3: 4,  # Guessed on 2s snippet
    4: 3,  # Guessed on 4s snippet
    5: 2,  # Guessed on 8s snippet
    6: 1,  # Guessed on 15s snippet
}
COIN_REWARD_MIN = 5
COIN_REWARD_MAX = 8
STREAK_BONUS_INTERVAL = 7
STREAK_BONUS_COINS = 50
MAX_DAILY_SNIPPET = 6
SUPPORTED_DAILY_MODES = supported_daily_modes()
DAILY_GENRE_ROTATION = [
    ('rock', 'Rock'),
    ('pop', 'Pop'),
    ('hiphop', 'Hip-Hop'),
    ('rnb', 'R&B'),
]
DAILY_DECADE_ROTATION = [
    ('1970s', 1970, 1979),
    ('1980s', 1980, 1989),
    ('1990s', 1990, 1999),
    ('2000s', 2000, 2009),
]
DAILY_GENRE_FALLBACK_ALIASES = {
    'rock': ['rock', 'alternative'],
    'pop': ['pop'],
    'hiphop': ['hip hop', 'hip-hop', 'rap'],
    'rnb': ['r&b', 'rnb', 'soul'],
}


def _coins_for_correct_guess(snippet_number):
    # Reward 8 coins for first try, taper to a 5-coin floor.
    return max(COIN_REWARD_MIN, COIN_REWARD_MAX + 1 - int(snippet_number))


def _daily_game_max_retries():
    return max(0, int(getattr(settings, 'DAILY_GAME_MAX_RETRIES', 2)))


def _daily_game_retry_coin_cost():
    return max(0, int(getattr(settings, 'DAILY_GAME_RETRY_COIN_COST', 120)))


def _max_hosted_rooms_per_user():
    return max(1, int(getattr(settings, 'MAX_HOSTED_ROOMS_PER_USER', 5)))


def _max_room_creations_per_day():
    return max(1, int(getattr(settings, 'MAX_ROOM_CREATIONS_PER_DAY', 5)))


def _daily_chat_group_name(room_id, mode):
    return f'chat_{room_id}_{mode}'


def _active_game_date():
    return active_game_date()


def _active_game_window(active_date):
    return active_game_window(active_date)


def _broadcast_leaderboard_updated(room_id, user_id, mode):
    channel_layer = get_channel_layer()
    if channel_layer is None:
        return

    try:
        async_to_sync(channel_layer.group_send)(
            _daily_chat_group_name(room_id, mode),
            {
                'type': 'leaderboard_updated',
                'room_id': str(room_id),
                'user_id': str(user_id),
                'mode': mode,
            },
        )
    except Exception:
        logger.exception(
            'Failed to broadcast leaderboard_updated for room %s mode %s.',
            room_id,
            mode,
        )


def _create_idempotent_message(model, *, lookup, defaults):
    try:
        with transaction.atomic():
            return model.objects.get_or_create(**lookup, defaults=defaults)
    except IntegrityError:
        return model.objects.get(**lookup), False


def _next_retry_requirement(game_session):
    if game_session.retry_credits > 0:
        return None
    max_retries = _daily_game_max_retries()
    if game_session.retries_used >= max_retries:
        return None
    return 'ad' if game_session.retries_used == 0 else 'coins'


def _retry_state_payload(game_session):
    next_requirement = None
    retry_available = game_session.retry_credits > 0
    if game_session.awaiting_retry_unlock and game_session.retry_credits == 0:
        next_requirement = _next_retry_requirement(game_session)
        retry_available = bool(next_requirement)
    return {
        'retry_available': retry_available,
        'next_retry_requirement': next_requirement,
        'retry_cost_coins': _daily_game_retry_coin_cost(),
        'retry_credits': game_session.retry_credits,
        'retries_used': game_session.retries_used,
        'awaiting_retry_unlock': game_session.awaiting_retry_unlock,
    }


def _is_hardcore_mode(mode):
    return mode == DAILY_MODE_HARDCORE


def _mode_rule_restricted_response(message, *, reason):
    return error_response(
        code=ErrorCode.MODE_RULE_RESTRICTED,
        message=message,
        status_code=status.HTTP_400_BAD_REQUEST,
        reason=reason,
    )


def _parse_daily_mode(request, *, default=DAILY_MODE_MIX):
    mode = request.query_params.get('mode')
    if mode is None and hasattr(request, 'data'):
        try:
            mode = request.data.get('mode')
        except Exception:
            mode = None
    mode = (mode or default).strip().lower()
    if mode not in SUPPORTED_DAILY_MODES:
        return None
    return mode


def _invalid_daily_mode_response():
    return Response(
        {'error': f'Invalid mode. Supported values: {", ".join(sorted(SUPPORTED_DAILY_MODES))}'},
        status=status.HTTP_400_BAD_REQUEST,
    )


def _daily_mode_locked_response(mode):
    return Response(
        {
            'error': (
                f'{daily_mode_label(mode)} is locked for this room. '
                'Contribute coins to unlock it first.'
            )
        },
        status=status.HTTP_403_FORBIDDEN,
    )


def _ensure_daily_mode_access(room, mode, active_date):
    if not is_daily_mode_enabled(mode):
        return _invalid_daily_mode_response()
    if is_daily_mode_accessible(room, mode, active_date):
        return None
    return _daily_mode_locked_response(mode)


def _get_or_create_room_daily_mode_state(room, mode):
    state, _created = RoomDailyModeState.objects.get_or_create(
        room=room,
        mode=mode,
    )
    return state


def _broadcast_room_mode_updated(room, *, activity_message, actor_user_id=None):
    channel_layer = get_channel_layer()
    if channel_layer is None:
        return

    try:
        async_to_sync(channel_layer.group_send)(
            f'chat_{room.id}',
            {
                'type': 'room_mode_updated',
                'room_id': str(room.id),
                'daily_modes': serialize_room_daily_modes(room, _active_game_date()),
                'activity_message': activity_message,
                'actor_user_id': str(actor_user_id) if actor_user_id else None,
            },
        )
    except Exception:
        logger.exception(
            'Failed to broadcast room_mode_updated for room %s.',
            room.id,
        )


def _daily_genre_for_date(target_date):
    start_index = target_date.toordinal() % len(DAILY_GENRE_ROTATION)
    for offset in range(len(DAILY_GENRE_ROTATION)):
        genre_key, genre_name = DAILY_GENRE_ROTATION[(start_index + offset) % len(DAILY_GENRE_ROTATION)]
        if _genre_track_queryset(genre_key).exists():
            return genre_key, genre_name
    return DAILY_GENRE_ROTATION[start_index]


def _daily_decade_for_date(target_date):
    start_index = target_date.toordinal() % len(DAILY_DECADE_ROTATION)
    for offset in range(len(DAILY_DECADE_ROTATION)):
        decade_label, start_year, end_year = DAILY_DECADE_ROTATION[
            (start_index + offset) % len(DAILY_DECADE_ROTATION)
        ]
        if _decade_track_queryset(start_year, end_year).exists():
            return decade_label, start_year, end_year
    return DAILY_DECADE_ROTATION[start_index]


def _daily_song_filter(room, date, mode):
    return DailySong.objects.filter(room=room, date=date, mode=mode)


def _used_track_ids_for_mode(room, mode):
    return DailySong.objects.filter(room=room, mode=mode).values_list('track_id', flat=True)


def _same_day_daily_exclusion_ids(room, date, mode):
    return DailySong.objects.filter(room=room, date=date).exclude(mode=mode).values_list('track_id', flat=True)


def _genre_track_queryset(genre_key):
    pack_tracks = Track.objects.filter(
        in_packs__pack__category=genre_key,
    ).distinct()
    if pack_tracks.exists():
        return pack_tracks

    aliases = DAILY_GENRE_FALLBACK_ALIASES.get(genre_key, [genre_key])
    query = Q()
    for alias in aliases:
        query |= Q(genre__icontains=alias)
    return Track.objects.filter(query).distinct()


def _decade_track_queryset(start_year, end_year):
    return Track.objects.filter(
        release_year__gte=start_year,
        release_year__lte=end_year,
    ).distinct()


def _choose_track_from_queryset(queryset, excluded_ids=()):
    candidates = queryset.exclude(id__in=excluded_ids)
    candidates_with_deezer = candidates.filter(deezer_id__isnull=False)
    if candidates_with_deezer.exists():
        return random.choice(list(candidates_with_deezer))
    if candidates.exists():
        return random.choice(list(candidates))
    return None


def _select_daily_track(room, date, mode):
    excluded_ids = set(_same_day_daily_exclusion_ids(room, date, mode))
    if mode == DAILY_MODE_GENRE:
        genre_key, genre_name = _daily_genre_for_date(date)
        base_queryset = _genre_track_queryset(genre_key)
        used_track_ids = set(_used_track_ids_for_mode(room, mode))

        track = _choose_track_from_queryset(base_queryset, excluded_ids | used_track_ids)
        if track is None:
            track = _choose_track_from_queryset(base_queryset, excluded_ids)
        if track is None:
            return None, genre_key, genre_name
        return track, genre_key, genre_name

    if mode == DAILY_MODE_DECADE:
        decade_label, start_year, end_year = _daily_decade_for_date(date)
        base_queryset = _decade_track_queryset(start_year, end_year)
        used_track_ids = set(_used_track_ids_for_mode(room, mode))

        track = _choose_track_from_queryset(base_queryset, excluded_ids | used_track_ids)
        if track is None:
            track = _choose_track_from_queryset(base_queryset, excluded_ids)
        if track is None:
            return None, decade_label, decade_label
        return track, decade_label, decade_label

    used_track_ids = set(_used_track_ids_for_mode(room, mode))
    base_queryset = Track.objects.all()

    track = _choose_track_from_queryset(base_queryset, excluded_ids | used_track_ids)
    if track is None:
        track = _choose_track_from_queryset(base_queryset, excluded_ids)
    if track is None:
        track = _choose_track_from_queryset(base_queryset)
    return track, None, None


def _get_or_create_daily_song(room, date, mode):
    daily_song = _daily_song_filter(room, date, mode).select_related('track').first()
    if daily_song:
        return daily_song

    track, genre_key, genre_name = _select_daily_track(room, date, mode)
    if track is None:
        return None

    return DailySong.objects.create(
        room=room,
        track=track,
        mode=mode,
        genre_key=genre_key,
        genre_name=genre_name,
        date=date,
    )

# Pack bundle constants
PACK_BUNDLE_STAGE_POINTS = {
    1: 4,
    2: 3,
    3: 2,
    4: 1,
}
PACK_BUNDLE_STAGE_ORDER = ['drums_url', 'bass_url', 'other_url', 'vocals_url']


def _get_room_from_request(request):
    room_id = request.query_params.get('room_id') or request.data.get('room_id')
    if not room_id:
        return None
    return get_object_or_404(Room, id=room_id)



def update_user_stats(user, points, won, played_date, perfect_game=False):
    user.games_played += 1
    if won:
        user.games_won += 1
    user.total_points += points
    if perfect_game:
        user.perfect_games += 1
    user.save(update_fields=['games_played', 'games_won', 'total_points', 'perfect_games'])
    user.update_streak(won, played_date)


def _get_pack_bundle_stems(pack_track, stage):
    stage = max(1, min(stage, len(PACK_BUNDLE_STAGE_ORDER)))
    stems = []
    for field in PACK_BUNDLE_STAGE_ORDER[:stage]:
        url = getattr(pack_track.track, field, None)
        if url:
            stems.append({'type': field.replace('_url', ''), 'url': url})
    return stems


def _make_stem_urls_absolute(request, stems):
    for stem in stems:
        url = stem.get('url')
        if url and url.startswith('/'):
            stem['url'] = request.build_absolute_uri(url)
    return stems


def _pack_track_stems_missing(pack_track):
    track = pack_track.track
    return not all([
        track.vocals_url,
        track.drums_url,
        track.bass_url,
        track.other_url,
    ])


def _get_stems_status_and_enqueue(pack_track):
    if not pack_track or not _pack_track_stems_missing(pack_track):
        return 'ready'

    job = PackBundleStemJob.objects.filter(pack_track=pack_track).first()
    if job and job.status in (PackBundleStemJob.STATUS_QUEUED, PackBundleStemJob.STATUS_RUNNING):
        return 'generating'

    if not job:
        job = PackBundleStemJob.objects.create(pack_track=pack_track, status=PackBundleStemJob.STATUS_QUEUED)
    else:
        job.status = PackBundleStemJob.STATUS_QUEUED
        job.error_message = ''
        job.started_at = None
        job.completed_at = None
        job.save(update_fields=['status', 'error_message', 'started_at', 'completed_at'])

    generate_pack_stems_task.delay(str(pack_track.id))
    return 'generating'


def _get_ordered_pack_tracks(pack):
    return list(pack.pack_tracks.select_related('track').order_by('order_in_pack', 'id'))


def _sync_room_pack_state(room_pack, today=None):
    today = today or _active_game_date()
    if not room_pack:
        return None
    if room_pack.is_active and room_pack.is_complete_for_date(today):
        room_pack.is_active = False
        room_pack.completed_on = room_pack.final_active_date()
        room_pack.save(update_fields=['is_active', 'completed_on'])
    return room_pack


def _sync_room_pack_states_for_room(room, today=None):
    today = today or _active_game_date()
    for room_pack in RoomPack.objects.filter(room=room, is_active=True).select_related('pack'):
        _sync_room_pack_state(room_pack, today=today)


def _get_active_room_pack(room, today=None):
    today = today or _active_game_date()
    _sync_room_pack_states_for_room(room, today=today)
    return RoomPack.objects.filter(room=room, is_active=True).select_related('pack').first()


def _get_room_pack(room, pack, today=None):
    room_pack = RoomPack.objects.filter(room=room, pack=pack).select_related('pack').first()
    if not room_pack:
        return None
    return _sync_room_pack_state(room_pack, today=today)


def _ensure_active_room_pack(room, pack, today=None):
    today = today or _active_game_date()
    room_pack = _get_room_pack(room, pack, today=today)
    if not room_pack:
        return None, Response(
            {'error': 'This pack is not owned by the room'},
            status=status.HTTP_403_FORBIDDEN,
        )

    if room_pack.completed_on:
        return None, Response(
            {'error': 'Pack already completed for this room'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    active_room_pack = _get_active_room_pack(room, today=today)
    if not active_room_pack:
        return None, Response(
            {'error': 'Activate this pack before playing it'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    if active_room_pack.id != room_pack.id:
        return None, Response(
            {
                'error': (
                    f'Another pack is already active in this room: '
                    f'{active_room_pack.pack.name}'
                )
            },
            status=status.HTTP_409_CONFLICT,
        )

    return room_pack, None


def _get_daily_pack_track(room, pack, today):
    daily_track = PackDailyTrack.objects.filter(room=room, pack=pack, date=today).first()
    if daily_track:
        return daily_track

    room_pack = _get_room_pack(room, pack, today=today)
    pack_tracks = _get_ordered_pack_tracks(pack)
    if not pack_tracks:
        return None

    if room_pack and room_pack.activated_on:
        day_index = (today - room_pack.activated_on).days
        if day_index < 0 or day_index >= len(pack_tracks):
            return None
        track = pack_tracks[day_index].track
        daily_track, _ = PackDailyTrack.objects.get_or_create(
            room=room,
            pack=pack,
            date=today,
            defaults={'track': track},
        )
        return daily_track

    used_track_ids = PackDailyTrack.objects.filter(
        room=room,
        pack=pack
    ).values_list('track_id', flat=True)
    used_ids = set(used_track_ids)
    available_tracks = [pt.track for pt in pack_tracks if pt.track_id not in used_ids]
    if not available_tracks:
        available_tracks = [pt.track for pt in pack_tracks]

    track = random.choice(available_tracks)
    daily_track, _ = PackDailyTrack.objects.get_or_create(
        room=room,
        pack=pack,
        date=today,
        defaults={'track': track},
    )
    return daily_track


class RoomCreateView(APIView):
    """
    Create a new permanent game room with auto-generated code.

    POST /api/game/rooms/create/
    Headers: Authorization: Bearer <access_token>
    Body: {} (empty - room code is auto-generated)
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        hosted_rooms_count = Room.objects.filter(host_user=request.user).count()
        max_hosted_rooms = _max_hosted_rooms_per_user()
        if hosted_rooms_count >= max_hosted_rooms:
            return error_response(
                code=ErrorCode.ROOM_LIMIT_REACHED,
                message=(
                    f'Room limit reached ({max_hosted_rooms} hosted rooms). '
                    f'Delete or leave one room before creating another.'
                ),
                status_code=status.HTTP_400_BAD_REQUEST,
                params={'max_rooms': max_hosted_rooms},
            )

        today = timezone.now().date()
        created_today_count = Room.objects.filter(
            host_user=request.user,
            created_at__date=today,
        ).count()
        max_creations_per_day = _max_room_creations_per_day()
        if created_today_count >= max_creations_per_day:
            return error_response(
                code=ErrorCode.DAILY_ROOM_CREATION_LIMIT_REACHED,
                message=(
                    f'Daily room creation limit reached ({max_creations_per_day}/day). '
                    f'Try again tomorrow.'
                ),
                status_code=status.HTTP_400_BAD_REQUEST,
                params={'daily_limit': max_creations_per_day},
            )

        # Create new room with auto-generated code
        serializer = RoomCreateSerializer(data={})
        if serializer.is_valid():
            room = serializer.save(host_user=request.user)

            # Automatically add the host to the room
            RoomUser.objects.create(room=room, user=request.user)

            # Auto-unlock packs flagged for automatic room unlock
            free_packs = SongPack.objects.filter(auto_unlock=True)
            for pack in free_packs:
                RoomPack.objects.get_or_create(
                    room=room,
                    pack=pack,
                    defaults={'coins_spent': 0, 'purchased_by': request.user}
                )

            response_serializer = RoomSerializer(
                room,
                context={'request': request, 'active_game_date': _active_game_date()},
            )
            return Response({
                'room': response_serializer.data,
                'message': 'Room created successfully'
            }, status=status.HTTP_201_CREATED)

        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class RoomJoinView(APIView):
    """
    Join an existing room.

    POST /api/game/rooms/join/
    Headers: Authorization: Bearer <access_token>
    Body: {
        "room_code": "ABCD1234"
    }
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = JoinRoomSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        room_code = serializer.validated_data['room_code']
        room = get_object_or_404(Room, room_code=room_code)

        # Check if user is already in the room
        if RoomUser.objects.filter(room=room, user=request.user).exists():
            return error_response(
                code=ErrorCode.ALREADY_IN_ROOM,
                message='You are already in this room',
                status_code=status.HTTP_400_BAD_REQUEST,
            )

        # Add user to room
        RoomUser.objects.create(room=room, user=request.user)

        response_serializer = RoomSerializer(
            room,
            context={'request': request, 'active_game_date': _active_game_date()},
        )
        return Response({
            'room': response_serializer.data,
            'message': 'Joined room successfully'
        }, status=status.HTTP_200_OK)


class RoomLeaveView(APIView):
    """
    Leave a room.
    Room is deleted if everyone leaves.

    POST /api/game/rooms/<room_id>/leave/
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def post(self, request, room_id):
        room = get_object_or_404(Room, id=room_id)

        # Check if user is in the room
        room_user = RoomUser.objects.filter(room=room, user=request.user).first()
        if not room_user:
            return error_response(
                code=ErrorCode.NOT_IN_ROOM,
                message='You are not in this room',
                status_code=status.HTTP_400_BAD_REQUEST,
            )

        # Remove user from room
        room_user.delete()

        # Check if room is now empty
        remaining_users = RoomUser.objects.filter(room=room).first()
        if not remaining_users:
            # Room is empty, delete it
            room.delete()
            return Response({
                'message': 'You left the room. Room has been deleted as it was empty.'
            }, status=status.HTTP_200_OK)

        # If the host left and there are other users, transfer host
        if room.host_user == request.user:
            room.host_user = remaining_users.user
            room.save()

        return Response({
            'message': 'Left room successfully'
        }, status=status.HTTP_200_OK)


class RoomDetailView(APIView):
    """
    Get details of a specific room.

    GET /api/game/rooms/<room_id>/
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, room_id):
        room = get_object_or_404(Room, id=room_id)
        _sync_room_pack_states_for_room(room)
        serializer = RoomSerializer(
            room,
            context={'request': request, 'active_game_date': _active_game_date()},
        )
        return Response(serializer.data, status=status.HTTP_200_OK)


class RoomDailyModeContributionView(APIView):
    """
    Contribute coins toward unlocking a paid daily mode for the room.

    POST /api/game/rooms/<room_id>/daily-modes/contribute/
    Body: {"mode": "genre", "amount": 20}
    """
    permission_classes = [IsAuthenticated]

    def post(self, request, room_id):
        room = get_object_or_404(Room, id=room_id)
        today = _active_game_date()

        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response(
                {'error': 'You must be in the room to contribute to daily modes'},
                status=status.HTTP_403_FORBIDDEN,
            )

        serializer = RoomDailyModeContributionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        mode = serializer.validated_data['mode']
        requested_amount = serializer.validated_data['amount']

        if mode == DAILY_MODE_MIX or is_daily_mode_free(mode):
            return Response(
                {'error': 'Daily Mix does not require coins'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if not is_daily_mode_enabled(mode):
            return _invalid_daily_mode_response()

        state = _get_or_create_room_daily_mode_state(room, mode)
        if is_daily_mode_accessible(room, mode, today, state_map={mode: state}):
            return Response(
                {'error': f'{daily_mode_label(mode)} is already unlocked for this room'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        cost = daily_mode_cost(mode)
        remaining_before = max(cost - state.progress_coins, 0)
        effective_amount = min(requested_amount, remaining_before)
        if effective_amount <= 0:
            return Response(
                {'error': f'{daily_mode_label(mode)} is already fully funded'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if request.user.coins < effective_amount:
            return error_response(
                code=ErrorCode.INSUFFICIENT_COINS,
                message='Insufficient coins',
                status_code=status.HTTP_400_BAD_REQUEST,
                params={'required_coins': effective_amount},
                coins=request.user.coins,
            )

        with transaction.atomic():
            if not request.user.spend_coins(
                effective_amount,
                reason=f'{daily_mode_label(mode)} contribution in room {room.room_code}',
            ):
                return error_response(
                    code=ErrorCode.INSUFFICIENT_COINS,
                    message='Insufficient coins',
                    status_code=status.HTTP_400_BAD_REQUEST,
                    params={'required_coins': effective_amount},
                    coins=request.user.coins,
                )

            state = RoomDailyModeState.objects.select_for_update().get(id=state.id)
            contribution, created = RoomDailyModeContribution.objects.get_or_create(
                state=state,
                user=request.user,
                defaults={'amount': effective_amount},
            )
            if not created:
                contribution.amount += effective_amount
                contribution.save(update_fields=['amount', 'updated_at'])

            state.progress_coins += effective_amount
            unlocked = state.progress_coins >= cost
            contributor_count = state.contributions.count()
            if unlocked:
                state.progress_coins = 0
                state.unlocked_for_date = today
                state.unlocked_until_date = (
                    today + timedelta(days=daily_mode_unlock_days(mode) - 1)
                )
                state.last_unlocked_at = timezone.now()
                state.last_unlock_contributor_count = contributor_count
                state.save(
                    update_fields=[
                        'progress_coins',
                        'unlocked_for_date',
                        'unlocked_until_date',
                        'last_unlocked_at',
                        'last_unlock_contributor_count',
                        'updated_at',
                    ]
                )
                state.contributions.all().delete()
            else:
                state.save(update_fields=['progress_coins', 'updated_at'])

        room_data = RoomSerializer(
            room,
            context={'request': request, 'active_game_date': today},
        ).data
        activity_message = (
            f'{request.user.username} unlocked {daily_mode_label(mode)} for this room.'
            if unlocked
            else f'{request.user.username} contributed {effective_amount} coins to {daily_mode_label(mode)}.'
        )
        _broadcast_room_mode_updated(
            room,
            activity_message=activity_message,
            actor_user_id=request.user.id,
        )
        return Response(
            {
                'room': room_data,
                'mode': mode,
                'contributed_coins': effective_amount,
                'coins': request.user.coins,
                'is_unlocked': unlocked,
                'message': (
                    f'{daily_mode_label(mode)} unlocked for this room'
                    if unlocked
                    else (
                        f'Contributed {effective_amount} coins to {daily_mode_label(mode)} '
                        f'({max(remaining_before - effective_amount, 0)} remaining)'
                    )
                ),
                'activity_message': activity_message,
            },
            status=status.HTTP_200_OK,
        )


class RoomRenameView(APIView):
    """
    Rename a room. Only the host can rename the room.

    PUT /api/game/rooms/<room_id>/rename/
    Headers: Authorization: Bearer <access_token>
    Body: {"name": "My Room Name"} or {"name": ""} to clear the name
    """
    permission_classes = [IsAuthenticated]

    def put(self, request, room_id):
        room = get_object_or_404(Room, id=room_id)

        # Check if user is the host
        if room.host_user != request.user:
            return error_response(
                code=ErrorCode.ONLY_HOST_CAN_RENAME_ROOM,
                message='Only the host can rename the room.',
                status_code=status.HTTP_403_FORBIDDEN,
            )

        serializer = RoomRenameSerializer(data=request.data)
        if serializer.is_valid():
            room.name = serializer.validated_data.get('name')
            room.save()

            return Response({
                'room': RoomSerializer(
                    room,
                    context={'request': request, 'active_game_date': _active_game_date()},
                ).data,
                'message': 'Room renamed successfully.'
            }, status=status.HTTP_200_OK)

        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class MyRoomsView(APIView):
    """
    Get all rooms the authenticated user is in.

    GET /api/game/rooms/my-rooms/
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        # Get all room_user entries for this user
        room_users = RoomUser.objects.filter(user=request.user).select_related('room')
        rooms = [ru.room for ru in room_users]
        for room in rooms:
            _sync_room_pack_states_for_room(room)
        serializer = RoomSerializer(
            rooms,
            many=True,
            context={'request': request, 'active_game_date': _active_game_date()},
        )
        return Response(serializer.data, status=status.HTTP_200_OK)


class SongPackListView(APIView):
    """
    Get list of all available song packs for purchase.
    Shows pack name, description, icon, and track count only.
    Track details are hidden until purchased.

    GET /api/game/packs/
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        room = _get_room_from_request(request)
        if not room:
            return Response({'error': 'room_id is required'}, status=status.HTTP_400_BAD_REQUEST)
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({'error': 'You must be in the room to view packs'}, status=status.HTTP_403_FORBIDDEN)
        _sync_room_pack_states_for_room(room)
        packs = SongPack.objects.all()
        serializer = SongPackListSerializer(
            packs,
            many=True,
            context={
                'request': request,
                'room': room,
                'active_game_date': _active_game_date(),
            },
        )
        return Response(serializer.data, status=status.HTTP_200_OK)


class SongPackDetailView(APIView):
    """
    Get full details (including tracks) for a pack the user owns.

    GET /api/game/packs/<pack_id>/
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, pack_id):
        room = _get_room_from_request(request)
        if not room:
            return Response({'error': 'room_id is required'}, status=status.HTTP_400_BAD_REQUEST)
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({'error': 'You must be in the room to view this pack'}, status=status.HTTP_403_FORBIDDEN)
        _sync_room_pack_states_for_room(room)
        pack = get_object_or_404(SongPack, id=pack_id)
        serializer = SongPackDetailSerializer(
            pack,
            context={
                'request': request,
                'room': room,
                'active_game_date': _active_game_date(),
            },
        )
        return Response(serializer.data, status=status.HTTP_200_OK)


class SongPackPurchaseView(APIView):
    """
    Purchase a song pack using coins.

    POST /api/game/packs/<pack_id>/purchase/
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def post(self, request, pack_id):
        room = _get_room_from_request(request)
        if not room:
            return Response({'error': 'room_id is required'}, status=status.HTTP_400_BAD_REQUEST)
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({'error': 'You must be in the room to purchase packs'}, status=status.HTTP_403_FORBIDDEN)
        pack = get_object_or_404(SongPack, id=pack_id)
        _sync_room_pack_states_for_room(room)

        if RoomPack.objects.filter(room=room, pack=pack).exists():
            serializer = SongPackDetailSerializer(
                pack,
                context={
                    'request': request,
                    'room': room,
                    'active_game_date': _active_game_date(),
                },
            )
            return Response({
                'pack': serializer.data,
                'coins': request.user.coins,
                'message': 'Pack already owned'
            }, status=status.HTTP_200_OK)

        if pack.is_free or pack.price_coins == 0:
            RoomPack.objects.get_or_create(
                room=room,
                pack=pack,
                defaults={'coins_spent': 0, 'purchased_by': request.user}
            )
            serializer = SongPackDetailSerializer(
                pack,
                context={
                    'request': request,
                    'room': room,
                    'active_game_date': _active_game_date(),
                },
            )
            return Response({
                'pack': serializer.data,
                'coins': request.user.coins,
                'message': 'Pack unlocked'
            }, status=status.HTTP_200_OK)

        if request.user.coins < pack.price_coins:
            return Response({
                'error': 'Insufficient coins',
                'coins': request.user.coins,
                'price_coins': pack.price_coins
            }, status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            if not request.user.spend_coins(pack.price_coins, reason=f"Purchased pack {pack.name}"):
                return Response({
                    'error': 'Insufficient coins',
                    'coins': request.user.coins,
                    'price_coins': pack.price_coins
                }, status=status.HTTP_400_BAD_REQUEST)

            RoomPack.objects.create(
                room=room,
                pack=pack,
                coins_spent=pack.price_coins,
                purchased_by=request.user
            )

        serializer = SongPackDetailSerializer(
            pack,
            context={
                'request': request,
                'room': room,
                'active_game_date': _active_game_date(),
            },
        )
        return Response({
            'pack': serializer.data,
            'coins': request.user.coins,
            'message': 'Pack purchased successfully'
        }, status=status.HTTP_200_OK)


class RoomPackActivateView(APIView):
    """
    Activate an owned room pack. Only one room pack can be active at a time.

    POST /api/game/rooms/<room_id>/packs/<pack_id>/activate/
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def post(self, request, room_id, pack_id):
        room = get_object_or_404(Room, id=room_id)
        pack = get_object_or_404(SongPack, id=pack_id)
        today = _active_game_date()

        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({'error': 'You must be in the room to activate packs'}, status=status.HTTP_403_FORBIDDEN)

        room_pack = _get_room_pack(room, pack, today=today)
        if not room_pack:
            return Response({'error': 'This pack is not owned by the room'}, status=status.HTTP_403_FORBIDDEN)

        if room_pack.completed_on:
            return Response({'error': 'This pack is already completed for the room'}, status=status.HTTP_400_BAD_REQUEST)

        if room_pack.total_days <= 0:
            return Response({'error': 'Pack has no tracks'}, status=status.HTTP_400_BAD_REQUEST)

        active_room_pack = _get_active_room_pack(room, today=today)
        if active_room_pack and active_room_pack.id != room_pack.id:
            return Response(
                {
                    'error': (
                        f'Another pack is already active in this room: '
                        f'{active_room_pack.pack.name}'
                    )
                },
                status=status.HTTP_409_CONFLICT,
            )

        if not room_pack.is_active:
            room_pack.is_active = True
            room_pack.activated_on = today
            room_pack.completed_on = None
            room_pack.save(update_fields=['is_active', 'activated_on', 'completed_on'])

        pack_serializer = SongPackDetailSerializer(
            pack,
            context={
                'request': request,
                'room': room,
                'active_game_date': today,
            },
        )
        room_serializer = RoomSerializer(
            room,
            context={
                'request': request,
                'active_game_date': today,
            },
        )
        return Response(
            {
                'pack': pack_serializer.data,
                'room': room_serializer.data,
                'message': 'Pack activated successfully',
            },
            status=status.HTTP_200_OK,
        )


class MyPacksView(APIView):
    """
    Get all packs the user can access (owned or free).

    GET /api/game/packs/my/
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        room = _get_room_from_request(request)
        if not room:
            return Response({'error': 'room_id is required'}, status=status.HTTP_400_BAD_REQUEST)
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({'error': 'You must be in the room to view packs'}, status=status.HTTP_403_FORBIDDEN)
        _sync_room_pack_states_for_room(room)
        packs = SongPack.objects.filter(room_purchases__room=room).distinct()
        serializer = SongPackListSerializer(
            packs,
            many=True,
            context={
                'request': request,
                'room': room,
                'active_game_date': _active_game_date(),
            },
        )
        return Response(serializer.data, status=status.HTTP_200_OK)


class PackBundleSessionView(APIView):
    """
    Start or get a bundle-like pack session (stem guessing).

    GET /api/game/rooms/<room_id>/packs/<pack_id>/bundle/
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, room_id, pack_id):
        room = get_object_or_404(Room, id=room_id)
        pack = get_object_or_404(SongPack, id=pack_id)
        today = _active_game_date()

        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({'error': 'You must be in the room to play this pack'}, status=status.HTTP_403_FORBIDDEN)

        _, error = _ensure_active_room_pack(room, pack, today=today)
        if error:
            return error

        daily_track = _get_daily_pack_track(room, pack, today)
        if not daily_track:
            return Response({'error': 'Pack has no tracks'}, status=status.HTTP_404_NOT_FOUND)

        session, _ = PackBundleSession.objects.get_or_create(
            room=room,
            user=request.user,
            pack=pack,
            pack_daily_track=daily_track,
            defaults={'current_stage': 1}
        )

        serializer = PackBundleSessionSerializer(session)
        stems = []
        stems_status = 'ready'
        if not session.completed_at:
            current_pack_track = PackTrack.objects.filter(pack=pack, track=daily_track.track).first()
            if current_pack_track:
                stems = _get_pack_bundle_stems(current_pack_track, session.current_stage)
                stems_status = _get_stems_status_and_enqueue(current_pack_track)

        return Response({
            'session': serializer.data,
            'stems': _make_stem_urls_absolute(request, stems),
            'stems_status': stems_status,
        }, status=status.HTTP_200_OK)


class PackBundleSkipView(APIView):
    """
    Skip to the next instrument stage (or next track) in a pack bundle.

    POST /api/game/rooms/<room_id>/packs/<pack_id>/bundle/skip/
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def post(self, request, room_id, pack_id):
        room = get_object_or_404(Room, id=room_id)
        pack = get_object_or_404(SongPack, id=pack_id)
        today = _active_game_date()

        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({'error': 'You must be in the room to play this pack'}, status=status.HTTP_403_FORBIDDEN)

        _, error = _ensure_active_room_pack(room, pack, today=today)
        if error:
            return error

        daily_track = _get_daily_pack_track(room, pack, today)
        session = PackBundleSession.objects.filter(
            room=room,
            user=request.user,
            pack=pack,
            pack_daily_track=daily_track
        ).first()
        if not session:
            return Response({'error': 'No active pack session. Start with GET bundle.'}, status=status.HTTP_400_BAD_REQUEST)

        if session.completed_at:
            return Response({'error': 'Pack already completed'}, status=status.HTTP_400_BAD_REQUEST)

        last_stage = len(PACK_BUNDLE_STAGE_ORDER)
        if session.current_stage >= last_stage:
            return Response({
                'error': 'You must submit a guess on the last stage'
            }, status=status.HTTP_400_BAD_REQUEST)

        session.current_stage += 1
        session.save(update_fields=['current_stage'])

        serializer = PackBundleSessionSerializer(session)
        stems = []
        stems_status = 'ready'
        if not session.completed_at:
            current_pack_track = PackTrack.objects.filter(pack=pack, track=daily_track.track).first()
            if current_pack_track:
                stems = _get_pack_bundle_stems(current_pack_track, session.current_stage)
                stems_status = _get_stems_status_and_enqueue(current_pack_track)

        return Response({
            'session': serializer.data,
            'stems': _make_stem_urls_absolute(request, stems),
            'stems_status': stems_status,
            'message': 'Skipped to next stage',
        }, status=status.HTTP_200_OK)


class PackBundleGuessView(APIView):
    """
    Submit a guess for the current pack bundle stage.

    POST /api/game/rooms/<room_id>/packs/<pack_id>/bundle/guess/
    Headers: Authorization: Bearer <access_token>
    Body: {"track_id": "uuid-of-guessed-track"}
    """
    permission_classes = [IsAuthenticated]

    def post(self, request, room_id, pack_id):
        room = get_object_or_404(Room, id=room_id)
        pack = get_object_or_404(SongPack, id=pack_id)
        today = _active_game_date()

        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({'error': 'You must be in the room to play this pack'}, status=status.HTTP_403_FORBIDDEN)

        _, error = _ensure_active_room_pack(room, pack, today=today)
        if error:
            return error

        daily_track = _get_daily_pack_track(room, pack, today)
        session = PackBundleSession.objects.filter(
            room=room,
            user=request.user,
            pack=pack,
            pack_daily_track=daily_track
        ).first()
        if not session:
            return Response({'error': 'No active pack session. Start with GET bundle.'}, status=status.HTTP_400_BAD_REQUEST)

        if session.completed_at:
            return Response({'error': 'Pack already completed'}, status=status.HTTP_400_BAD_REQUEST)

        serializer = PackBundleGuessSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        current_pack_track = PackTrack.objects.filter(pack=pack, track=daily_track.track).first()
        if not current_pack_track:
            return Response({'error': 'Pack track not found'}, status=status.HTTP_404_NOT_FOUND)
        attempt_count = PackBundleAttempt.objects.filter(
            session=session,
            pack_track=current_pack_track,
            stage=session.current_stage
        ).count()
        max_attempts_for_stage = (
            1
            if session.current_stage < len(PACK_BUNDLE_STAGE_ORDER)
            else 1 + session.retries_used + session.retry_credits
        )
        if attempt_count >= max_attempts_for_stage:
            return Response({'error': 'Already guessed for this stage'}, status=status.HTTP_400_BAD_REQUEST)

        guessed_track = Track.objects.get(id=serializer.validated_data['track_id'])
        stage_guessed = session.current_stage
        is_correct = guessed_track.id == current_pack_track.track_id
        points_awarded = PACK_BUNDLE_STAGE_POINTS.get(stage_guessed, 0) if is_correct else 0

        PackBundleAttempt.objects.create(
            session=session,
            pack_track=current_pack_track,
            stage=stage_guessed,
            guessed_track=guessed_track,
            is_correct=is_correct,
            points_awarded=points_awarded
        )

        session.points_earned += points_awarded

        if is_correct:
            session.current_stage = stage_guessed + 1
            session.awaiting_retry_unlock = False
            session.completed_at = timezone.now()
            session.save(update_fields=[
                'points_earned',
                'current_stage',
                'awaiting_retry_unlock',
                'completed_at',
            ])
        elif stage_guessed < len(PACK_BUNDLE_STAGE_ORDER):
            session.current_stage += 1
            session.awaiting_retry_unlock = False
            session.save(update_fields=[
                'points_earned',
                'current_stage',
                'awaiting_retry_unlock',
            ])
        elif session.retry_credits > 0:
            session.retry_credits -= 1
            session.retries_used += 1
            next_requirement = _next_retry_requirement(session)
            if next_requirement is not None:
                session.awaiting_retry_unlock = True
                session.save(update_fields=[
                    'points_earned',
                    'retry_credits',
                    'retries_used',
                    'awaiting_retry_unlock',
                ])
                retry_message = (
                    'Incorrect. Watch an ad to unlock your next chance.'
                    if next_requirement == 'ad'
                    else f'Incorrect. Spend {_daily_game_retry_coin_cost()} coins to unlock one final chance.'
                )
                response_serializer = PackBundleSessionSerializer(session)
                return Response({
                    'session': response_serializer.data,
                    'stems': _make_stem_urls_absolute(request, _get_pack_bundle_stems(current_pack_track, session.current_stage)),
                    'stems_status': _get_stems_status_and_enqueue(current_pack_track),
                    'is_correct': False,
                    'points_awarded': 0,
                    'game_over': False,
                    'message': retry_message,
                }, status=status.HTTP_200_OK)

            session.awaiting_retry_unlock = False
            session.completed_at = timezone.now()
            session.save(update_fields=[
                'points_earned',
                'retry_credits',
                'retries_used',
                'awaiting_retry_unlock',
                'completed_at',
            ])
        else:
            next_requirement = _next_retry_requirement(session)
            if next_requirement is not None:
                session.awaiting_retry_unlock = True
                session.save(update_fields=[
                    'points_earned',
                    'awaiting_retry_unlock',
                ])
                retry_message = (
                    'Incorrect. Watch an ad to unlock a second chance.'
                    if next_requirement == 'ad'
                    else f'Incorrect. Spend {_daily_game_retry_coin_cost()} coins to unlock one final chance.'
                )
                response_serializer = PackBundleSessionSerializer(session)
                return Response({
                    'session': response_serializer.data,
                    'stems': _make_stem_urls_absolute(request, _get_pack_bundle_stems(current_pack_track, session.current_stage)),
                    'stems_status': _get_stems_status_and_enqueue(current_pack_track),
                    'is_correct': False,
                    'points_awarded': 0,
                    'game_over': False,
                    'message': retry_message,
                }, status=status.HTTP_200_OK)

            session.awaiting_retry_unlock = False
            session.completed_at = timezone.now()
            session.save(update_fields=[
                'points_earned',
                'awaiting_retry_unlock',
                'completed_at',
            ])

        response_serializer = PackBundleSessionSerializer(session)
        stems = []
        stems_status = 'ready'
        if not session.completed_at:
            stems = _get_pack_bundle_stems(current_pack_track, session.current_stage)
            stems_status = _get_stems_status_and_enqueue(current_pack_track)

        return Response({
            'session': response_serializer.data,
            'stems': _make_stem_urls_absolute(request, stems),
            'stems_status': stems_status,
            'is_correct': is_correct,
            'points_awarded': points_awarded,
            'game_over': session.completed_at is not None,
        }, status=status.HTTP_200_OK)


class PackBundleRetryView(APIView):
    """
    Activate an extra guess after failing on the last pack bundle stage.

    POST /api/game/rooms/<room_id>/packs/<pack_id>/bundle/retry/
    Headers: Authorization: Bearer <access_token>
    Body: {"action": "ad" | "coins" | "forfeit"}
    """
    permission_classes = [IsAuthenticated]

    def post(self, request, room_id, pack_id):
        room = get_object_or_404(Room, id=room_id)
        pack = get_object_or_404(SongPack, id=pack_id)
        today = _active_game_date()

        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return error_response(
                code=ErrorCode.MUST_BE_IN_ROOM_TO_PLAY_GAME,
                message='You must be in the room to play this pack',
                status_code=status.HTTP_403_FORBIDDEN,
            )

        _, error = _ensure_active_room_pack(room, pack, today=today)
        if error:
            return error

        serializer = DailyGameRetrySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        action = serializer.validated_data['action']

        daily_track = _get_daily_pack_track(room, pack, today)
        session = PackBundleSession.objects.filter(
            room=room,
            user=request.user,
            pack=pack,
            pack_daily_track=daily_track,
        ).first()
        if not session:
            return error_response(
                code=ErrorCode.NO_ACTIVE_GAME_SESSION,
                message='No active pack session. Start by calling GET /bundle/.',
                status_code=status.HTTP_400_BAD_REQUEST,
            )

        if session.completed_at:
            return error_response(
                code=ErrorCode.GAME_ALREADY_COMPLETED,
                message='Pack already completed',
                status_code=status.HTTP_400_BAD_REQUEST,
            )

        if session.current_stage < len(PACK_BUNDLE_STAGE_ORDER):
            return error_response(
                code=ErrorCode.RETRY_AFTER_LAST_SNIPPET_ONLY,
                message='Retry is only available after reaching the last stage',
                status_code=status.HTTP_400_BAD_REQUEST,
                session=PackBundleSessionSerializer(session).data,
            )

        if action == 'forfeit':
            session.retry_credits = 0
            session.awaiting_retry_unlock = False
            session.completed_at = timezone.now()
            session.save(update_fields=[
                'retry_credits',
                'awaiting_retry_unlock',
                'completed_at',
            ])

            return Response(
                {
                    'game_over': True,
                    'guess_counted': False,
                    'points_earned': session.points_earned,
                    'message': 'Challenge ended. Better luck next time!',
                    'session': PackBundleSessionSerializer(session).data,
                    'stems': [],
                    'stems_status': 'ready',
                },
                status=status.HTTP_200_OK,
            )

        if session.retry_credits > 0:
            return error_response(
                code=ErrorCode.RETRY_ALREADY_ACTIVE,
                message='A retry is already active',
                status_code=status.HTTP_400_BAD_REQUEST,
                session=PackBundleSessionSerializer(session).data,
            )

        if not session.awaiting_retry_unlock:
            return error_response(
                code=ErrorCode.RETRY_NOT_PENDING_UNLOCK,
                message='No retry is pending unlock yet',
                status_code=status.HTTP_400_BAD_REQUEST,
                session=PackBundleSessionSerializer(session).data,
            )

        expected_action = _next_retry_requirement(session)
        if expected_action is None:
            return error_response(
                code=ErrorCode.NO_RETRIES_REMAINING,
                message='No retries remaining',
                status_code=status.HTTP_400_BAD_REQUEST,
                session=PackBundleSessionSerializer(session).data,
            )

        if action != expected_action:
            return error_response(
                code=ErrorCode.INVALID_RETRY_ACTION,
                message=f'Invalid retry action. Expected "{expected_action}"',
                status_code=status.HTTP_400_BAD_REQUEST,
                params={'expected_action': expected_action},
                expected_action=expected_action,
                session=PackBundleSessionSerializer(session).data,
            )

        with transaction.atomic():
            if action == 'coins':
                retry_cost = _daily_game_retry_coin_cost()
                if request.user.coins < retry_cost:
                    return error_response(
                        code=ErrorCode.INSUFFICIENT_COINS,
                        message='Insufficient coins',
                        status_code=status.HTTP_400_BAD_REQUEST,
                        params={'required_coins': retry_cost},
                        coins=request.user.coins,
                        retry_cost_coins=retry_cost,
                        session=PackBundleSessionSerializer(session).data,
                    )

                if not request.user.spend_coins(retry_cost, reason=f"Pack retry in room {room.room_code}"):
                    return error_response(
                        code=ErrorCode.INSUFFICIENT_COINS,
                        message='Insufficient coins',
                        status_code=status.HTTP_400_BAD_REQUEST,
                        params={'required_coins': retry_cost},
                    )

            session.retry_credits += 1
            session.awaiting_retry_unlock = False
            session.save(update_fields=['retry_credits', 'awaiting_retry_unlock'])

        current_pack_track = PackTrack.objects.filter(
            pack=pack,
            track=daily_track.track,
        ).first()
        stems = (
            []
            if current_pack_track is None
            else _get_pack_bundle_stems(current_pack_track, session.current_stage)
        )
        stems_status = (
            'ready'
            if current_pack_track is None
            else _get_stems_status_and_enqueue(current_pack_track)
        )

        return Response(
            {
                'message': 'Retry unlocked. Make another guess.',
                'coins': request.user.coins,
                'session': PackBundleSessionSerializer(session).data,
                'stems': _make_stem_urls_absolute(request, stems),
                'stems_status': stems_status,
            },
            status=status.HTTP_200_OK,
        )


class PackBundleLeaderboardView(APIView):
    """
    Get leaderboard for today's pack bundle in a room.

    GET /api/game/rooms/<room_id>/packs/<pack_id>/bundle/leaderboard/
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, room_id, pack_id):
        room = get_object_or_404(Room, id=room_id)
        pack = get_object_or_404(SongPack, id=pack_id)
        today = _active_game_date()

        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({'error': 'You must be in the room to view leaderboard'}, status=status.HTTP_403_FORBIDDEN)

        _, error = _ensure_active_room_pack(room, pack, today=today)
        if error:
            return error

        daily_track = _get_daily_pack_track(room, pack, today)
        if not daily_track:
            return Response({'error': 'Pack has no tracks'}, status=status.HTTP_404_NOT_FOUND)

        sessions = PackBundleSession.objects.filter(
            room=room,
            pack=pack,
            pack_daily_track=daily_track,
            completed_at__isnull=False,
        ).select_related('user').order_by('-points_earned', 'completed_at')

        leaderboard = []
        for session in sessions:
            correct_attempt = PackBundleAttempt.objects.filter(
                session=session,
                is_correct=True
            ).order_by('stage').first()
            if correct_attempt:
                stage_number = correct_attempt.stage
            else:
                stage_number = max(1, min(session.current_stage - 1, len(PACK_BUNDLE_STAGE_ORDER)))
            leaderboard.append({
                'user': {
                    'id': str(session.user.id),
                    'username': session.user.username,
                    'email': session.user.email
                },
                'points_earned': session.points_earned,
                'stage_number': stage_number,
                'completed_at': session.completed_at
            })

        return Response({
            'date': today,
            'leaderboard': leaderboard
        }, status=status.HTTP_200_OK)


class PackBundleMessagesView(APIView):
    """
    Get or post messages for a pack bundle (scoped per room/pack/day).

    GET /api/game/rooms/<room_id>/packs/<pack_id>/bundle/messages/?limit=50&offset=0
    POST /api/game/rooms/<room_id>/packs/<pack_id>/bundle/messages/
    Headers: Authorization: Bearer <access_token>

    Rate limited: POST 30 messages per minute
    """
    permission_classes = [IsAuthenticated]

    def get_throttles(self):
        if self.request.method == 'POST':
            return [MessageRateThrottle()]
        return []

    def get(self, request, room_id, pack_id):
        room = get_object_or_404(Room, id=room_id)
        pack = get_object_or_404(SongPack, id=pack_id)
        today = _active_game_date()

        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({
                'error': 'You must be in the room to view messages'
            }, status=status.HTTP_403_FORBIDDEN)

        _, error = _ensure_active_room_pack(room, pack, today=today)
        if error:
            return error

        daily_track = _get_daily_pack_track(room, pack, today)
        if not daily_track:
            return Response({'error': 'Pack has no tracks'}, status=status.HTTP_404_NOT_FOUND)

        limit = int(request.query_params.get('limit', 50))
        offset = int(request.query_params.get('offset', 0))
        limit = min(limit, 100)

        messages = PackBundleMessage.objects.filter(
            room=room,
            pack=pack,
            pack_daily_track=daily_track,
        ).select_related('user')[offset:offset + limit]

        serializer = PackBundleMessageSerializer(messages, many=True)
        return Response({
            'messages': serializer.data,
            'limit': limit,
            'offset': offset
        }, status=status.HTTP_200_OK)

    def post(self, request, room_id, pack_id):
        room = get_object_or_404(Room, id=room_id)
        pack = get_object_or_404(SongPack, id=pack_id)
        today = _active_game_date()

        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({
                'error': 'You must be in the room to post messages'
            }, status=status.HTTP_403_FORBIDDEN)

        _, error = _ensure_active_room_pack(room, pack, today=today)
        if error:
            return error

        daily_track = _get_daily_pack_track(room, pack, today)
        if not daily_track:
            return Response({'error': 'Pack has no tracks'}, status=status.HTTP_404_NOT_FOUND)

        serializer = PostMessageSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        client_message_id = serializer.validated_data.get('client_message_id')
        message_text = serializer.validated_data['message']
        if client_message_id:
            message, created = _create_idempotent_message(
                PackBundleMessage,
                lookup={
                    'room': room,
                    'pack': pack,
                    'pack_daily_track': daily_track,
                    'user': request.user,
                    'client_message_id': client_message_id,
                },
                defaults={'message': message_text},
            )
        else:
            message = PackBundleMessage.objects.create(
                room=room,
                pack=pack,
                pack_daily_track=daily_track,
                user=request.user,
                message=message_text,
            )
            created = True

        response_serializer = PackBundleMessageSerializer(message)
        return Response(
            response_serializer.data,
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


class TrackListView(APIView):
    """
    Get list of all tracks (for admin purposes).

    GET /api/game/tracks/
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        tracks = Track.objects.all()
        serializer = TrackSerializer(tracks, many=True)
        return Response(serializer.data, status=status.HTTP_200_OK)


class TrackRefreshPreviewView(APIView):
    """
    Refresh a track preview URL from Deezer if the cached one is expired.

    POST /api/game/tracks/<track_id>/refresh-preview/
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def post(self, request, track_id):
        track = get_object_or_404(Track, id=track_id)
        preview_url = track.get_fresh_preview_url(prefer_cached=False, force_refresh=True)
        serializer = TrackSerializer(track)
        return Response({
            'track': serializer.data,
            'preview_url': preview_url,
        }, status=status.HTTP_200_OK)


class RoomDailySongView(APIView):
    """
    Get today's song for a specific room.
    If no song exists for today, automatically selects a random one.

    GET /api/game/rooms/<room_id>/daily-song/
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, room_id):
        room = get_object_or_404(Room, id=room_id)
        today = _active_game_date()
        mode = _parse_daily_mode(request)
        if mode is None:
            return _invalid_daily_mode_response()

        # Check if user is in the room
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({
                'error': 'You must be in the room to see the daily song'
            }, status=status.HTTP_403_FORBIDDEN)

        access_error = _ensure_daily_mode_access(room, mode, today)
        if access_error:
            return access_error

        daily_song = _get_or_create_daily_song(room, today, mode)
        if not daily_song:
            return Response({
                'error': 'No tracks available. Please populate tracks using: python manage.py fetch_deezer_tracks'
            }, status=status.HTTP_404_NOT_FOUND)

        serializer = TrackSerializer(daily_song.track)
        return Response({
            'track': serializer.data,
            'mode': daily_song.mode,
            'genre_key': daily_song.genre_key,
            'genre_name': daily_song.genre_name,
            'date': today,
            'message': 'Today\'s song'
        }, status=status.HTTP_200_OK)


class DailyGameView(APIView):
    """
    Get or create today's game session for a room.
    Returns the daily song and user's current progress.

    GET /api/game/rooms/<room_id>/daily-game/
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, room_id):
        room = get_object_or_404(Room, id=room_id)
        today = _active_game_date()
        mode = _parse_daily_mode(request)
        if mode is None:
            return _invalid_daily_mode_response()

        # Check if user is in the room
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({
                'error': 'You must be in the room to play the game'
            }, status=status.HTTP_403_FORBIDDEN)

        access_error = _ensure_daily_mode_access(room, mode, today)
        if access_error:
            return access_error

        daily_song = _get_or_create_daily_song(room, today, mode)
        if not daily_song:
            return Response({
                'error': 'No tracks available. Please populate tracks using: python manage.py fetch_deezer_tracks'
            }, status=status.HTTP_404_NOT_FOUND)

        # Get or create game session for this user
        game_session, created = DailyGameSession.objects.get_or_create(
            room=room,
            user=request.user,
            daily_song=daily_song,
            defaults={'current_snippet': 1}
        )

        serializer = GameSessionSerializer(game_session)
        data = serializer.data

        # Get fresh preview URL from Deezer if track has deezer_id
        if daily_song.track.deezer_id:
            fresh_preview_url = daily_song.track.get_fresh_preview_url(prefer_cached=True)
            if fresh_preview_url:
                data['daily_song']['track']['preview_url'] = fresh_preview_url

        return Response(data, status=status.HTTP_200_OK)


class SkipSnippetView(APIView):
    """
    Skip to the next snippet without guessing.

    POST /api/game/rooms/<room_id>/daily-game/skip/
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def post(self, request, room_id):
        room = get_object_or_404(Room, id=room_id)
        today = _active_game_date()
        mode = _parse_daily_mode(request)
        if mode is None:
            return _invalid_daily_mode_response()
        mode = _parse_daily_mode(request)
        if mode is None:
            return _invalid_daily_mode_response()

        # Check if user is in the room
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({
                'error': 'You must be in the room to play the game'
            }, status=status.HTTP_403_FORBIDDEN)

        access_error = _ensure_daily_mode_access(room, mode, today)
        if access_error:
            return access_error

        # Get today's song and user's session
        daily_song = _daily_song_filter(room, today, mode).first()
        if not daily_song:
            return Response({
                'error': 'No song available for today'
            }, status=status.HTTP_404_NOT_FOUND)

        game_session = DailyGameSession.objects.filter(
            room=room,
            user=request.user,
            daily_song=daily_song
        ).first()

        if not game_session:
            return Response({
                'error': 'No active game session. Start by calling GET /daily-game/'
            }, status=status.HTTP_400_BAD_REQUEST)

        # Check if already completed
        if game_session.completed_at or game_session.correct_guess:
            return Response({
                'error': 'Game already completed',
                'current_snippet': game_session.current_snippet
            }, status=status.HTTP_400_BAD_REQUEST)

        # Check if already at max snippets
        if game_session.current_snippet >= MAX_DAILY_SNIPPET:
            return Response({
                'error': 'Already at maximum snippet level',
                'current_snippet': MAX_DAILY_SNIPPET
            }, status=status.HTTP_400_BAD_REQUEST)

        # Increment snippet
        game_session.current_snippet += 1
        game_session.save()

        if game_session.current_snippet == MAX_DAILY_SNIPPET:
            _broadcast_leaderboard_updated(room.id, request.user.id, mode)

        return Response({
            'current_snippet': game_session.current_snippet,
            'message': f'Skipped to snippet {game_session.current_snippet}'
        }, status=status.HTTP_200_OK)


class SubmitGuessView(APIView):
    """
    Submit a guess for today's song.

    POST /api/game/rooms/<room_id>/daily-game/guess/
    Headers: Authorization: Bearer <access_token>
    Body: {"track_id": "uuid-of-guessed-track"}

    Rate limited: 10 guesses per minute
    """
    permission_classes = [IsAuthenticated]
    throttle_classes = [GuessRateThrottle]

    def post(self, request, room_id):
        room = get_object_or_404(Room, id=room_id)
        today = _active_game_date()
        mode = _parse_daily_mode(request)
        if mode is None:
            return _invalid_daily_mode_response()

        # Check if user is in the room
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({
                'error': 'You must be in the room to play the game'
            }, status=status.HTTP_403_FORBIDDEN)

        access_error = _ensure_daily_mode_access(room, mode, today)
        if access_error:
            return access_error

        # Validate input
        serializer = SubmitGuessSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        guessed_track_id = serializer.validated_data['track_id']

        # Get today's song and user's session
        daily_song = _daily_song_filter(room, today, mode).first()
        if not daily_song:
            return Response({
                'error': 'No song available for today'
            }, status=status.HTTP_404_NOT_FOUND)

        game_session = DailyGameSession.objects.filter(
            room=room,
            user=request.user,
            daily_song=daily_song
        ).first()

        if not game_session:
            return Response({
                'error': 'No active game session. Start by calling GET /daily-game/'
            }, status=status.HTTP_400_BAD_REQUEST)

        # Check if already completed
        if game_session.completed_at or game_session.correct_guess:
            return Response({
                'error': 'Game already completed',
                'correct_answer': {
                    'title': daily_song.track.title,
                    'artist': daily_song.track.artist
                }
            }, status=status.HTTP_400_BAD_REQUEST)

        # User must unlock retry before additional guesses at snippet 6.
        if (
            game_session.current_snippet >= MAX_DAILY_SNIPPET
            and game_session.awaiting_retry_unlock
            and game_session.retry_credits == 0
        ):
            next_requirement = _next_retry_requirement(game_session)
            if next_requirement == 'ad':
                retry_message = 'Watch an ad to unlock your next chance.'
            elif next_requirement == 'coins':
                retry_message = (
                    f'Spend {_daily_game_retry_coin_cost()} coins to unlock your final chance.'
                )
            else:
                retry_message = 'No retries remaining.'

            return Response({
                'is_correct': False,
                'current_snippet': game_session.current_snippet,
                'game_over': False,
                'guess_counted': False,
                'message': retry_message,
                **_retry_state_payload(game_session),
            }, status=status.HTTP_200_OK)

        # Get the guessed track for recording
        guessed_track = Track.objects.get(id=guessed_track_id)

        # Validate guess by comparing track IDs
        is_correct = str(guessed_track_id) == str(daily_song.track.id)

        # Record the guess attempt
        GuessAttempt.objects.create(
            game_session=game_session,
            snippet_number=game_session.current_snippet,
            guessed_title=guessed_track.title,
            guessed_artist=guessed_track.artist,
            is_correct=is_correct
        )

        game_session.guesses_made += 1

        if is_correct:
            # Correct guess - award points and complete
            points = SNIPPET_POINTS.get(game_session.current_snippet, 0)
            game_session.correct_guess = True
            game_session.points_earned = points
            game_session.completed_at = timezone.now()
            game_session.awaiting_retry_unlock = False
            game_session.save(update_fields=[
                'guesses_made',
                'correct_guess',
                'points_earned',
                'completed_at',
                'awaiting_retry_unlock',
            ])

            coins_awarded = _coins_for_correct_guess(game_session.current_snippet)
            streak_bonus = 0
            with transaction.atomic():
                if coins_awarded:
                    request.user.add_coins(
                        coins_awarded,
                        reason=f"Correct guess in room {room.room_code}"
                    )

                update_user_stats(
                    request.user,
                    points=points,
                    won=True,
                    played_date=today,
                    perfect_game=(game_session.current_snippet == 1)
                )

                # Weekly streak bonus: award bonus coins every 7th day
                request.user.refresh_from_db(fields=['current_streak'])
                if (request.user.current_streak > 0
                        and request.user.current_streak % STREAK_BONUS_INTERVAL == 0):
                    streak_bonus = STREAK_BONUS_COINS
                    request.user.add_coins(
                        streak_bonus,
                        reason=f"Weekly streak bonus ({request.user.current_streak}-day streak)",
                        transaction_type='bonus',
                    )

            _broadcast_leaderboard_updated(room.id, request.user.id, mode)

            response_data = {
                'is_correct': True,
                'points_earned': points,
                'coins_awarded': coins_awarded,
                'snippet_number': game_session.current_snippet,
                'game_over': True,
                'message': f'Correct! You earned {points} points!',
                'correct_answer': {
                    'title': daily_song.track.title,
                    'artist': daily_song.track.artist
                },
                **_retry_state_payload(game_session),
            }
            if streak_bonus:
                response_data['streak_bonus'] = streak_bonus
                response_data['streak_days'] = request.user.current_streak

            return Response(response_data, status=status.HTTP_200_OK)

        # Incorrect guess - move to next snippet if not at max
        if game_session.current_snippet < MAX_DAILY_SNIPPET:
            game_session.current_snippet += 1
            game_session.awaiting_retry_unlock = False
            game_session.save(update_fields=['guesses_made', 'current_snippet', 'awaiting_retry_unlock'])

            if game_session.current_snippet == MAX_DAILY_SNIPPET:
                _broadcast_leaderboard_updated(room.id, request.user.id, mode)

            return Response({
                'is_correct': False,
                'current_snippet': game_session.current_snippet,
                'game_over': False,
                'message': f'Incorrect. Try again with snippet {game_session.current_snippet}',
                **_retry_state_payload(game_session),
            }, status=status.HTTP_200_OK)

        if _is_hardcore_mode(mode):
            game_session.correct_guess = False
            game_session.points_earned = 0
            game_session.completed_at = timezone.now()
            game_session.awaiting_retry_unlock = False
            game_session.save(update_fields=[
                'guesses_made',
                'correct_guess',
                'points_earned',
                'completed_at',
                'awaiting_retry_unlock',
            ])

            update_user_stats(
                request.user,
                points=0,
                won=False,
                played_date=today,
                perfect_game=False,
            )
            _broadcast_leaderboard_updated(room.id, request.user.id, mode)

            return Response({
                'is_correct': False,
                'points_earned': 0,
                'game_over': True,
                'message': 'Hardcore mode gives one run only. No more chances.',
                'correct_answer': {
                    'title': daily_song.track.title,
                    'artist': daily_song.track.artist,
                },
                **_retry_state_payload(game_session),
            }, status=status.HTTP_200_OK)

        # At max snippet: consume available retry credit first.
        if game_session.retry_credits > 0:
            game_session.retry_credits -= 1
            game_session.retries_used += 1
            next_requirement = _next_retry_requirement(game_session)
            if next_requirement is not None:
                game_session.awaiting_retry_unlock = True
                game_session.save(update_fields=[
                    'guesses_made',
                    'retry_credits',
                    'retries_used',
                    'awaiting_retry_unlock',
                ])
                if next_requirement == 'ad':
                    retry_message = 'Incorrect. Watch an ad to unlock your next chance.'
                else:
                    retry_message = (
                        f'Incorrect. Spend {_daily_game_retry_coin_cost()} coins to unlock one final chance.'
                    )
                return Response({
                    'is_correct': False,
                    'current_snippet': game_session.current_snippet,
                    'game_over': False,
                    'message': retry_message,
                    **_retry_state_payload(game_session),
                }, status=status.HTTP_200_OK)

            # Retry attempt failed and no retries remain.
            game_session.awaiting_retry_unlock = False
            game_session.correct_guess = False
            game_session.points_earned = 0
            game_session.completed_at = timezone.now()
            game_session.save(update_fields=[
                'guesses_made',
                'retry_credits',
                'retries_used',
                'awaiting_retry_unlock',
                'correct_guess',
                'points_earned',
                'completed_at',
            ])
            update_user_stats(
                request.user,
                points=0,
                won=False,
                played_date=today,
                perfect_game=False
            )
            _broadcast_leaderboard_updated(room.id, request.user.id, mode)
            return Response({
                'is_correct': False,
                'points_earned': 0,
                'current_snippet': game_session.current_snippet,
                'game_over': True,
                'message': 'No more chances. Better luck next time!',
                'correct_answer': {
                    'title': daily_song.track.title,
                    'artist': daily_song.track.artist
                },
                **_retry_state_payload(game_session),
            }, status=status.HTTP_200_OK)

        next_requirement = _next_retry_requirement(game_session)
        if next_requirement is not None:
            game_session.awaiting_retry_unlock = True
            game_session.save(update_fields=['guesses_made', 'awaiting_retry_unlock'])
            if next_requirement == 'ad':
                retry_message = 'Incorrect. Watch an ad to unlock a second chance.'
            else:
                retry_message = (
                    f'Incorrect. Spend {_daily_game_retry_coin_cost()} coins to unlock one final chance.'
                )

            return Response({
                'is_correct': False,
                'current_snippet': game_session.current_snippet,
                'game_over': False,
                'message': retry_message,
                **_retry_state_payload(game_session),
            }, status=status.HTTP_200_OK)

        # No retries left - complete with 0 points and reveal answer.
        game_session.correct_guess = False
        game_session.points_earned = 0
        game_session.completed_at = timezone.now()
        game_session.awaiting_retry_unlock = False
        game_session.save(update_fields=[
            'guesses_made',
            'correct_guess',
            'points_earned',
            'completed_at',
            'awaiting_retry_unlock',
        ])

        update_user_stats(
            request.user,
            points=0,
            won=False,
            played_date=today,
            perfect_game=False
        )
        _broadcast_leaderboard_updated(room.id, request.user.id, mode)

        return Response({
            'is_correct': False,
            'points_earned': 0,
            'game_over': True,
            'message': 'No more chances. Better luck next time!',
            'correct_answer': {
                'title': daily_song.track.title,
                'artist': daily_song.track.artist
            },
            **_retry_state_payload(game_session),
        }, status=status.HTTP_200_OK)


class DailyGameRetryView(APIView):
    """
    Activate an extra guess after failing at the last snippet.

    POST /api/game/rooms/<room_id>/daily-game/retry/
    Headers: Authorization: Bearer <access_token>
    Body: {"action": "ad" | "coins" | "forfeit"}
    """
    permission_classes = [IsAuthenticated]

    def post(self, request, room_id):
        room = get_object_or_404(Room, id=room_id)
        today = _active_game_date()
        mode = _parse_daily_mode(request)
        if mode is None:
            return _invalid_daily_mode_response()

        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return error_response(
                code=ErrorCode.MUST_BE_IN_ROOM_TO_PLAY_GAME,
                message='You must be in the room to play the game',
                status_code=status.HTTP_403_FORBIDDEN,
            )

        access_error = _ensure_daily_mode_access(room, mode, today)
        if access_error:
            return access_error

        if _is_hardcore_mode(mode):
            return _mode_rule_restricted_response(
                'Hardcore mode does not allow retries.',
                reason='hardcore_retry_disabled',
            )

        serializer = DailyGameRetrySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        action = serializer.validated_data['action']

        daily_song = _daily_song_filter(room, today, mode).first()
        if not daily_song:
            return error_response(
                code=ErrorCode.NO_SONG_AVAILABLE_TODAY,
                message='No song available for today',
                status_code=status.HTTP_404_NOT_FOUND,
            )

        game_session = DailyGameSession.objects.filter(
            room=room,
            user=request.user,
            daily_song=daily_song,
        ).first()
        if not game_session:
            return error_response(
                code=ErrorCode.NO_ACTIVE_GAME_SESSION,
                message='No active game session. Start by calling GET /daily-game/',
                status_code=status.HTTP_400_BAD_REQUEST,
            )

        if game_session.completed_at or game_session.correct_guess:
            return error_response(
                code=ErrorCode.GAME_ALREADY_COMPLETED,
                message='Game already completed',
                status_code=status.HTTP_400_BAD_REQUEST,
            )

        if game_session.current_snippet < MAX_DAILY_SNIPPET:
            return error_response(
                code=ErrorCode.RETRY_AFTER_LAST_SNIPPET_ONLY,
                message='Retry is only available after reaching the last snippet',
                status_code=status.HTTP_400_BAD_REQUEST,
            )

        if action == 'forfeit':
            game_session.correct_guess = False
            game_session.points_earned = 0
            game_session.retry_credits = 0
            game_session.awaiting_retry_unlock = False
            game_session.completed_at = timezone.now()
            game_session.save(update_fields=[
                'correct_guess',
                'points_earned',
                'retry_credits',
                'awaiting_retry_unlock',
                'completed_at',
            ])

            update_user_stats(
                request.user,
                points=0,
                won=False,
                played_date=today,
                perfect_game=False,
            )
            _broadcast_leaderboard_updated(room.id, request.user.id, mode)

            return Response(
                {
                    'is_correct': False,
                    'game_over': True,
                    'guess_counted': False,
                    'points_earned': 0,
                    'message': 'Game ended. Better luck next time!',
                    'correct_answer': {
                        'title': daily_song.track.title,
                        'artist': daily_song.track.artist,
                    },
                    **_retry_state_payload(game_session),
                },
                status=status.HTTP_200_OK,
            )

        if game_session.retry_credits > 0:
            return error_response(
                code=ErrorCode.RETRY_ALREADY_ACTIVE,
                message='A retry is already active',
                status_code=status.HTTP_400_BAD_REQUEST,
                current_snippet=game_session.current_snippet,
                **_retry_state_payload(game_session),
            )

        if not game_session.awaiting_retry_unlock:
            return error_response(
                code=ErrorCode.RETRY_NOT_PENDING_UNLOCK,
                message='No retry is pending unlock yet',
                status_code=status.HTTP_400_BAD_REQUEST,
                current_snippet=game_session.current_snippet,
                **_retry_state_payload(game_session),
            )

        expected_action = _next_retry_requirement(game_session)
        if expected_action is None:
            return error_response(
                code=ErrorCode.NO_RETRIES_REMAINING,
                message='No retries remaining',
                status_code=status.HTTP_400_BAD_REQUEST,
                **_retry_state_payload(game_session),
            )

        if action != expected_action:
            return error_response(
                code=ErrorCode.INVALID_RETRY_ACTION,
                message=f'Invalid retry action. Expected "{expected_action}"',
                status_code=status.HTTP_400_BAD_REQUEST,
                params={'expected_action': expected_action},
                expected_action=expected_action,
                **_retry_state_payload(game_session),
            )

        with transaction.atomic():
            if action == 'coins':
                retry_cost = _daily_game_retry_coin_cost()
                if request.user.coins < retry_cost:
                    return error_response(
                        code=ErrorCode.INSUFFICIENT_COINS,
                        message='Insufficient coins',
                        status_code=status.HTTP_400_BAD_REQUEST,
                        params={'required_coins': retry_cost},
                        coins=request.user.coins,
                        retry_cost_coins=retry_cost,
                        **_retry_state_payload(game_session),
                    )

                if not request.user.spend_coins(retry_cost, reason=f"Daily retry in room {room.room_code}"):
                    return error_response(
                        code=ErrorCode.INSUFFICIENT_COINS,
                        message='Insufficient coins',
                        status_code=status.HTTP_400_BAD_REQUEST,
                        params={'required_coins': retry_cost},
                    )

            game_session.retry_credits += 1
            game_session.awaiting_retry_unlock = False
            game_session.save(update_fields=['retry_credits', 'awaiting_retry_unlock'])

        return Response(
            {
                'message': 'Retry unlocked. Make another guess.',
                'current_snippet': game_session.current_snippet,
                'coins': request.user.coins,
                **_retry_state_payload(game_session),
            },
            status=status.HTTP_200_OK,
        )


class LeaderboardView(APIView):
    """
    Get today's leaderboard for a room.

    GET /api/game/rooms/<room_id>/daily-game/leaderboard/
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, room_id):
        room = get_object_or_404(Room, id=room_id)
        today = _active_game_date()
        mode = _parse_daily_mode(request)
        if mode is None:
            return _invalid_daily_mode_response()

        # Check if user is in the room
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({
                'error': 'You must be in the room to view the leaderboard'
            }, status=status.HTTP_403_FORBIDDEN)

        access_error = _ensure_daily_mode_access(room, mode, today)
        if access_error:
            return access_error

        # Get today's song
        daily_song = _daily_song_filter(room, today, mode).first()
        if not daily_song:
            return Response({
                'error': 'No song available for today'
            }, status=status.HTTP_404_NOT_FOUND)

        # Include completed sessions plus players who reached the final snippet
        # without a correct guess, so "did not guess" entries appear in today's
        # results even before an explicit forfeit.
        sessions = DailyGameSession.objects.filter(
            room=room,
            daily_song=daily_song,
        ).filter(
            Q(completed_at__isnull=False)
            | Q(correct_guess=False, current_snippet=MAX_DAILY_SNIPPET)
        ).select_related('user').order_by('-correct_guess', '-points_earned', 'completed_at', 'created_at')

        # Build leaderboard entries
        leaderboard = []
        for session in sessions:
            leaderboard.append({
                'user': {
                    'id': str(session.user.id),
                    'username': session.user.username,
                    'email': session.user.email
                },
                'correct_guess': session.correct_guess,
                'points_earned': session.points_earned or 0,
                'snippet_number': session.current_snippet,
                'completed_at': session.completed_at or session.created_at
            })

        return Response({
            'date': today,
            'mode': mode,
            'genre_key': daily_song.genre_key,
            'genre_name': daily_song.genre_name,
            'leaderboard': leaderboard
        }, status=status.HTTP_200_OK)


class RoomMessagesView(APIView):
    """
    Get or post messages in a room.

    GET /api/game/rooms/<room_id>/messages/?limit=50&offset=0
    POST /api/game/rooms/<room_id>/messages/
    Headers: Authorization: Bearer <access_token>

    Rate limited: POST 30 messages per minute
    """
    permission_classes = [IsAuthenticated]

    def get_throttles(self):
        """Apply message throttle only to POST requests."""
        if self.request.method == 'POST':
            return [MessageRateThrottle()]
        return []

    def get(self, request, room_id):
        room = get_object_or_404(Room, id=room_id)
        active_date = _active_game_date()
        mode = _parse_daily_mode(request)
        if mode is None:
            return _invalid_daily_mode_response()

        # Check if user is in the room
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({
                'error': 'You must be in the room to view messages'
            }, status=status.HTTP_403_FORBIDDEN)

        access_error = _ensure_daily_mode_access(room, mode, active_date)
        if access_error:
            return access_error

        # Get pagination parameters
        limit = int(request.query_params.get('limit', 50))
        offset = int(request.query_params.get('offset', 0))

        # Limit max to 100 messages per request
        limit = min(limit, 100)

        # Get messages for the active daily-chat window.
        window_start, window_end = _active_game_window(active_date)
        messages = RoomMessage.objects.filter(
            room=room,
            mode=mode,
            created_at__gte=window_start,
            created_at__lt=window_end,
        ).select_related('user')[offset:offset + limit]

        serializer = RoomMessageSerializer(messages, many=True)
        return Response({
            'messages': serializer.data,
            'limit': limit,
            'offset': offset
        }, status=status.HTTP_200_OK)

    def post(self, request, room_id):
        room = get_object_or_404(Room, id=room_id)
        mode = _parse_daily_mode(request)
        if mode is None:
            return _invalid_daily_mode_response()

        # Check if user is in the room
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({
                'error': 'You must be in the room to post messages'
            }, status=status.HTTP_403_FORBIDDEN)

        access_error = _ensure_daily_mode_access(room, mode, _active_game_date())
        if access_error:
            return access_error

        # Validate message
        serializer = PostMessageSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        client_message_id = serializer.validated_data.get('client_message_id')
        message_text = serializer.validated_data['message']
        if client_message_id:
            message, created = _create_idempotent_message(
                RoomMessage,
                lookup={
                    'room': room,
                    'mode': mode,
                    'user': request.user,
                    'client_message_id': client_message_id,
                },
                defaults={'message': message_text},
            )
        else:
            message = RoomMessage.objects.create(
                room=room,
                mode=mode,
                user=request.user,
                message=message_text,
            )
            created = True

        response_serializer = RoomMessageSerializer(message)
        return Response(
            response_serializer.data,
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


HINT_COSTS = {
    'genre': 30,
    'decade': 60,
    'artist_name': 100,
}


class DailyGameHintView(APIView):
    """
    Purchase a hint for the current daily game session.

    POST /api/game/rooms/<room_id>/daily-game/hint/
    Headers: Authorization: Bearer <access_token>
    Body: {"hint_type": "genre" | "decade" | "artist_name"}

    Hint types and costs (sequential — buy in order):
    - genre: Reveal the track genre (30 coins)
    - decade: Reveal the release decade (60 coins)
    - artist_name: Reveal the full artist name (100 coins)
    """
    permission_classes = [IsAuthenticated]

    def post(self, request, room_id):
        room = get_object_or_404(Room, id=room_id)
        today = _active_game_date()
        mode = _parse_daily_mode(request)
        if mode is None:
            return _invalid_daily_mode_response()

        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({'error': 'You must be in the room to use hints'}, status=status.HTTP_403_FORBIDDEN)

        access_error = _ensure_daily_mode_access(room, mode, today)
        if access_error:
            return access_error

        if _is_hardcore_mode(mode):
            return _mode_rule_restricted_response(
                'Hardcore mode does not allow hints.',
                reason='hardcore_hints_disabled',
            )

        hint_type = request.data.get('hint_type', '').strip()
        if hint_type not in HINT_COSTS:
            return Response(
                {'error': f'Invalid hint_type. Must be one of: {", ".join(HINT_COSTS.keys())}'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        daily_song = _daily_song_filter(room, today, mode).select_related('track').first()
        if not daily_song:
            return Response({'error': 'No song available for today'}, status=status.HTTP_404_NOT_FOUND)

        game_session = DailyGameSession.objects.filter(
            room=room, user=request.user, daily_song=daily_song
        ).first()
        if not game_session:
            return Response({'error': 'No active game session.'}, status=status.HTTP_400_BAD_REQUEST)

        if game_session.completed_at or game_session.correct_guess:
            return Response({'error': 'Game already completed.'}, status=status.HTTP_400_BAD_REQUEST)

        # Check if hint already purchased
        if hint_type in game_session.hints_used:
            # Return the hint data without charging again
            hint_value = self._get_hint_value(hint_type, daily_song.track)
            return Response({
                'hint_type': hint_type,
                'hint_value': hint_value,
                'already_owned': True,
                'coins': request.user.coins,
            }, status=status.HTTP_200_OK)

        cost = HINT_COSTS[hint_type]
        if request.user.coins < cost:
            return Response({
                'error': 'Insufficient coins',
                'coins': request.user.coins,
                'cost': cost,
            }, status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            if not request.user.spend_coins(cost, reason=f"Hint: {hint_type} in room {room.room_code}"):
                return Response({'error': 'Insufficient coins'}, status=status.HTTP_400_BAD_REQUEST)

            game_session.hints_used = game_session.hints_used + [hint_type]
            game_session.save(update_fields=['hints_used'])

        hint_value = self._get_hint_value(hint_type, daily_song.track)
        return Response({
            'hint_type': hint_type,
            'hint_value': hint_value,
            'cost': cost,
            'coins': request.user.coins,
        }, status=status.HTTP_200_OK)

    @staticmethod
    def _get_hint_value(hint_type, track):
        if hint_type == 'genre':
            return track.genre if track.genre else 'Unknown'
        elif hint_type == 'decade':
            if track.release_year:
                decade_start = (track.release_year // 10) * 10
                return f"{decade_start}s"
            return 'Unknown'
        elif hint_type == 'artist_name':
            return track.artist
        return None


class PackBundleHintView(APIView):
    """
    Purchase a hint for the current pack bundle session.

    POST /api/game/rooms/<room_id>/packs/<pack_id>/bundle/hint/
    Headers: Authorization: Bearer <access_token>
    Body: {"hint_type": "genre" | "decade" | "artist_name"}
    """
    permission_classes = [IsAuthenticated]

    def post(self, request, room_id, pack_id):
        room = get_object_or_404(Room, id=room_id)
        pack = get_object_or_404(SongPack, id=pack_id)
        today = _active_game_date()

        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({'error': 'You must be in the room to use hints'}, status=status.HTTP_403_FORBIDDEN)

        _, error = _ensure_active_room_pack(room, pack, today=today)
        if error:
            return error

        daily_track = _get_daily_pack_track(room, pack, today)
        if not daily_track:
            return Response({'error': 'Pack has no tracks'}, status=status.HTTP_404_NOT_FOUND)

        session = PackBundleSession.objects.filter(
            room=room, user=request.user, pack=pack, pack_daily_track=daily_track
        ).first()
        if not session:
            return Response({'error': 'No active pack session.'}, status=status.HTTP_400_BAD_REQUEST)

        if session.completed_at:
            return Response({'error': 'Pack session already completed.'}, status=status.HTTP_400_BAD_REQUEST)

        hint_type = request.data.get('hint_type', '').strip()
        if hint_type not in HINT_COSTS:
            return Response(
                {'error': f'Invalid hint_type. Must be one of: {", ".join(HINT_COSTS.keys())}'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        track = daily_track.track

        # Check if hint already purchased
        if hint_type in session.hints_used:
            hint_value = DailyGameHintView._get_hint_value(hint_type, track)
            return Response({
                'hint_type': hint_type,
                'hint_value': hint_value,
                'already_owned': True,
                'coins': request.user.coins,
            }, status=status.HTTP_200_OK)

        cost = HINT_COSTS[hint_type]
        if request.user.coins < cost:
            return Response({
                'error': 'Insufficient coins',
                'coins': request.user.coins,
                'cost': cost,
            }, status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            if not request.user.spend_coins(cost, reason=f"Hint: {hint_type} in pack {pack.name}"):
                return Response({'error': 'Insufficient coins'}, status=status.HTTP_400_BAD_REQUEST)

            session.hints_used = session.hints_used + [hint_type]
            session.save(update_fields=['hints_used'])

        hint_value = DailyGameHintView._get_hint_value(hint_type, track)
        return Response({
            'hint_type': hint_type,
            'hint_value': hint_value,
            'cost': cost,
            'coins': request.user.coins,
        }, status=status.HTTP_200_OK)


class SearchTracksView(APIView):
    """
    Search for tracks by title or artist.

    GET /api/game/tracks/search/?q=search_query
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        query = request.query_params.get('q', '').strip()
        try:
            limit = int(request.query_params.get('limit', 25))
        except (TypeError, ValueError):
            limit = 25
        limit = max(1, min(limit, 50))

        if not query:
            return Response([], status=status.HTTP_200_OK)

        # Search tracks by title or artist (case-insensitive)
        tracks = Track.objects.filter(
            Q(title__icontains=query) | Q(artist__icontains=query)
        ).annotate(
            relevance=Case(
                When(artist__iexact=query, then=Value(0)),
                When(title__iexact=query, then=Value(1)),
                When(artist__istartswith=query, then=Value(2)),
                When(title__istartswith=query, then=Value(3)),
                default=Value(4),
                output_field=IntegerField(),
            )
        ).order_by('relevance', 'artist', 'title', 'id')[:limit]

        serializer = TrackSerializer(tracks, many=True)
        return Response(serializer.data, status=status.HTTP_200_OK)


class UserGameHistoryView(APIView):
    """
    Get the authenticated user's completed game history.

    GET /api/game/history/?limit=30&offset=0
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        limit = int(request.query_params.get('limit', 30))
        offset = int(request.query_params.get('offset', 0))
        limit = min(limit, 100)

        sessions = DailyGameSession.objects.filter(
            user=request.user,
            completed_at__isnull=False
        ).select_related(
            'room', 'daily_song__track'
        ).order_by('-completed_at')

        serializer = GameHistoryEntrySerializer(
            sessions[offset:offset + limit],
            many=True
        )
        return Response({
            'results': serializer.data,
            'limit': limit,
            'offset': offset
        }, status=status.HTTP_200_OK)


class RoomHistoryListView(APIView):
    """
    List of past daily songs for a room with the user's result for each.
    Excludes the currently active game date.

    GET /api/game/rooms/<room_id>/history/?limit=30&offset=0
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, room_id):
        room = get_object_or_404(Room, id=room_id)
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({'error': 'You must be in the room to view history'}, status=status.HTTP_403_FORBIDDEN)
        mode = _parse_daily_mode(request)
        if mode is None:
            return _invalid_daily_mode_response()

        limit = min(int(request.query_params.get('limit', 30)), 100)
        offset = int(request.query_params.get('offset', 0))

        daily_songs = DailySong.objects.filter(
            room=room,
            mode=mode,
        ).exclude(
            date=_active_game_date(),
        ).select_related('track').order_by('-date')

        total = daily_songs.count()
        page = list(daily_songs[offset:offset + limit])

        session_map = {
            s.daily_song_id: s
            for s in DailyGameSession.objects.filter(
                room=room,
                user=request.user,
                daily_song__in=page,
            )
        }

        results = []
        for ds in page:
            session = session_map.get(ds.id)
            results.append({
                'date': ds.date.isoformat(),
                'mode': ds.mode,
                'genre_key': ds.genre_key,
                'genre_name': ds.genre_name,
                'track': {
                    'id': str(ds.track.id),
                    'title': ds.track.title,
                    'artist': ds.track.artist,
                    'cover_url': ds.track.cover_url,
                },
                'my_session': {
                    'correct_guess': session.correct_guess,
                    'points_earned': session.points_earned,
                    'current_snippet': session.current_snippet,
                    'guesses_made': session.guesses_made,
                } if session else None,
            })

        return Response({
            'results': results,
            'mode': mode,
            'limit': limit,
            'offset': offset,
            'total': total,
        }, status=status.HTTP_200_OK)


class RoomHistoryDetailView(APIView):
    """
    Full details for a specific past day in a room.

    GET /api/game/rooms/<room_id>/history/<date>/  (date: YYYY-MM-DD)
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, room_id, date):
        from datetime import date as date_type
        try:
            parsed_date = date_type.fromisoformat(date)
        except ValueError:
            return Response({'error': 'Invalid date format. Use YYYY-MM-DD.'}, status=status.HTTP_400_BAD_REQUEST)
        mode = _parse_daily_mode(request)
        if mode is None:
            return _invalid_daily_mode_response()

        room = get_object_or_404(Room, id=room_id)
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({'error': 'You must be in the room to view history'}, status=status.HTTP_403_FORBIDDEN)

        if parsed_date >= _active_game_date():
            return Response({'error': 'This date is not yet in history.'}, status=status.HTTP_400_BAD_REQUEST)

        daily_song = DailySong.objects.filter(
            room=room,
            date=parsed_date,
            mode=mode,
        ).select_related('track').first()
        if not daily_song:
            return Response({'error': 'No song found for this date.'}, status=status.HTTP_404_NOT_FOUND)

        session = DailyGameSession.objects.filter(
            room=room, user=request.user, daily_song=daily_song
        ).first()

        leaderboard_sessions = DailyGameSession.objects.filter(
            room=room,
            daily_song=daily_song,
            completed_at__isnull=False,
        ).select_related('user').order_by('-correct_guess', '-points_earned', 'completed_at')

        leaderboard = [
            {
                'user': {'id': str(s.user.id), 'username': s.user.username},
                'correct_guess': s.correct_guess,
                'points_earned': s.points_earned,
                'snippet_number': s.current_snippet,
                'completed_at': s.completed_at.isoformat() if s.completed_at else None,
            }
            for s in leaderboard_sessions
        ]

        window_start, window_end = _active_game_window(parsed_date)
        messages = RoomMessage.objects.filter(
            room=room,
            mode=daily_song.mode,
            created_at__gte=window_start,
            created_at__lt=window_end,
        ).select_related('user').order_by('created_at')

        return Response({
            'date': parsed_date.isoformat(),
            'mode': daily_song.mode,
            'genre_key': daily_song.genre_key,
            'genre_name': daily_song.genre_name,
            'track': {
                'id': str(daily_song.track.id),
                'title': daily_song.track.title,
                'artist': daily_song.track.artist,
                'cover_url': daily_song.track.cover_url,
                'preview_url': daily_song.track.preview_url,
            },
            'my_session': {
                'correct_guess': session.correct_guess,
                'points_earned': session.points_earned,
                'current_snippet': session.current_snippet,
                'guesses_made': session.guesses_made,
                'completed_at': session.completed_at.isoformat() if session.completed_at else None,
            } if session else None,
            'leaderboard': leaderboard,
            'messages': [
                {
                    'id': str(m.id),
                    'user': {'id': str(m.user.id), 'username': m.user.username},
                    'message': m.message,
                    'created_at': m.created_at.isoformat(),
                }
                for m in messages
            ],
        }, status=status.HTTP_200_OK)


class PackBundleHistoryListView(APIView):
    """
    List of past pack bundle tracks for a room/pack with the user's result.
    Excludes the currently active game date.

    GET /api/game/rooms/<room_id>/packs/<pack_id>/history/?limit=30&offset=0
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, room_id, pack_id):
        room = get_object_or_404(Room, id=room_id)
        pack = get_object_or_404(SongPack, id=pack_id)
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({'error': 'You must be in the room to view history'}, status=status.HTTP_403_FORBIDDEN)

        limit = min(int(request.query_params.get('limit', 30)), 100)
        offset = int(request.query_params.get('offset', 0))

        daily_tracks = PackDailyTrack.objects.filter(
            room=room, pack=pack,
        ).exclude(
            date=_active_game_date(),
        ).select_related('track').order_by('-date')

        total = daily_tracks.count()
        page = list(daily_tracks[offset:offset + limit])

        session_map = {
            s.pack_daily_track_id: s
            for s in PackBundleSession.objects.filter(
                room=room,
                user=request.user,
                pack=pack,
                pack_daily_track__in=page,
            )
        }

        results = []
        for dt in page:
            session = session_map.get(dt.id)
            results.append({
                'date': dt.date.isoformat(),
                'track': {
                    'id': str(dt.track.id),
                    'title': dt.track.title,
                    'artist': dt.track.artist,
                    'cover_url': dt.track.cover_url,
                },
                'my_session': {
                    'completed': session.completed_at is not None,
                    'points_earned': session.points_earned,
                    'current_stage': session.current_stage,
                } if session else None,
            })

        return Response({
            'results': results,
            'limit': limit,
            'offset': offset,
            'total': total,
        }, status=status.HTTP_200_OK)


class PackBundleHistoryDetailView(APIView):
    """
    Full details for a specific past day in a room/pack bundle.

    GET /api/game/rooms/<room_id>/packs/<pack_id>/history/<date>/  (date: YYYY-MM-DD)
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, room_id, pack_id, date):
        from datetime import date as date_type
        try:
            parsed_date = date_type.fromisoformat(date)
        except ValueError:
            return Response({'error': 'Invalid date format. Use YYYY-MM-DD.'}, status=status.HTTP_400_BAD_REQUEST)

        room = get_object_or_404(Room, id=room_id)
        pack = get_object_or_404(SongPack, id=pack_id)
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({'error': 'You must be in the room to view history'}, status=status.HTTP_403_FORBIDDEN)

        if parsed_date >= _active_game_date():
            return Response({'error': 'This date is not yet in history.'}, status=status.HTTP_400_BAD_REQUEST)

        daily_track = PackDailyTrack.objects.filter(
            room=room, pack=pack, date=parsed_date,
        ).select_related('track').first()
        if not daily_track:
            return Response({'error': 'No pack track found for this date.'}, status=status.HTTP_404_NOT_FOUND)

        session = PackBundleSession.objects.filter(
            room=room, user=request.user, pack=pack, pack_daily_track=daily_track,
        ).first()

        leaderboard_sessions = PackBundleSession.objects.filter(
            room=room, pack=pack, pack_daily_track=daily_track,
            completed_at__isnull=False,
        ).select_related('user').order_by('-points_earned', 'completed_at')

        leaderboard = [
            {
                'user': {'id': str(s.user.id), 'username': s.user.username},
                'points_earned': s.points_earned,
                'stage_number': s.current_stage,
                'completed_at': s.completed_at.isoformat(),
            }
            for s in leaderboard_sessions
        ]

        messages = PackBundleMessage.objects.filter(
            room=room, pack=pack,
            created_at__date=parsed_date,
        ).select_related('user').order_by('created_at')

        return Response({
            'date': parsed_date.isoformat(),
            'track': {
                'id': str(daily_track.track.id),
                'title': daily_track.track.title,
                'artist': daily_track.track.artist,
                'cover_url': daily_track.track.cover_url,
            },
            'my_session': {
                'completed': session.completed_at is not None,
                'points_earned': session.points_earned,
                'current_stage': session.current_stage,
                'completed_at': session.completed_at.isoformat() if session.completed_at else None,
            } if session else None,
            'leaderboard': leaderboard,
            'messages': [
                {
                    'id': str(m.id),
                    'user': {'id': str(m.user.id), 'username': m.user.username},
                    'message': m.message,
                    'created_at': m.created_at.isoformat(),
                }
                for m in messages
            ],
        }, status=status.HTTP_200_OK)
