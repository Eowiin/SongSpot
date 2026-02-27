from datetime import timedelta

from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django.conf import settings
from django.db import transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
import random


def _active_game_date():
    """
    Returns the 'active' date for daily game content.
    The day rolls over at 12:00 UTC when the cron pre-generates new content.
      - Before 12:00 UTC → yesterday's date (yesterday's song is still active)
      - From 12:00 UTC   → today's date
    """
    now = timezone.now()
    if now.hour < 12:
        return (now - timedelta(days=1)).date()
    return now.date()


from .models import (
    Track, SongPack, Room, RoomUser, RoomPack,
    DailySong, PackTrack, PackDailyTrack, PackBundleSession, PackBundleAttempt,
    DailyGameSession, GuessAttempt, RoomMessage, PackBundleMessage, PackBundleStemJob
)
from .serializers import (
    TrackSerializer,
    SongPackListSerializer,
    SongPackDetailSerializer,
    RoomSerializer,
    RoomCreateSerializer,
    RoomRenameSerializer,
    JoinRoomSerializer,
    GameSessionSerializer,
    SubmitGuessSerializer,
    DailyGameRetrySerializer,
    LeaderboardEntrySerializer,
    RoomMessageSerializer,
    PackBundleMessageSerializer,
    PostMessageSerializer,
    GameHistoryEntrySerializer,
    PackBundleSessionSerializer,
    PackBundleGuessSerializer,
)
from .tasks import generate_pack_stems_task
from songspot.throttling import GuessRateThrottle, MessageRateThrottle

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


def _get_daily_pack_track(room, pack, today):
    daily_track = PackDailyTrack.objects.filter(room=room, pack=pack, date=today).first()
    if daily_track:
        return daily_track

    pack_tracks = _get_ordered_pack_tracks(pack)
    if not pack_tracks:
        return None

    used_track_ids = PackDailyTrack.objects.filter(
        room=room,
        pack=pack
    ).values_list('track_id', flat=True)
    used_ids = set(used_track_ids)
    available_tracks = [pt.track for pt in pack_tracks if pt.track_id not in used_ids]
    if not available_tracks:
        available_tracks = [pt.track for pt in pack_tracks]

    track = random.choice(available_tracks)
    return PackDailyTrack.objects.create(room=room, pack=pack, track=track, date=today)


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
            return Response({
                'error': f'Room limit reached ({max_hosted_rooms} hosted rooms). '
                         f'Delete or leave one room before creating another.'
            }, status=status.HTTP_400_BAD_REQUEST)

        today = timezone.now().date()
        created_today_count = Room.objects.filter(
            host_user=request.user,
            created_at__date=today,
        ).count()
        max_creations_per_day = _max_room_creations_per_day()
        if created_today_count >= max_creations_per_day:
            return Response({
                'error': f'Daily room creation limit reached ({max_creations_per_day}/day). '
                         f'Try again tomorrow.'
            }, status=status.HTTP_400_BAD_REQUEST)

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

            response_serializer = RoomSerializer(room)
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
            return Response({
                'error': 'You are already in this room'
            }, status=status.HTTP_400_BAD_REQUEST)

        # Add user to room
        RoomUser.objects.create(room=room, user=request.user)

        response_serializer = RoomSerializer(room)
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
            return Response({
                'error': 'You are not in this room'
            }, status=status.HTTP_400_BAD_REQUEST)

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
        serializer = RoomSerializer(room)
        return Response(serializer.data, status=status.HTTP_200_OK)


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
            return Response(
                {'error': 'Only the host can rename the room.'},
                status=status.HTTP_403_FORBIDDEN
            )

        serializer = RoomRenameSerializer(data=request.data)
        if serializer.is_valid():
            room.name = serializer.validated_data.get('name')
            room.save()

            return Response({
                'room': RoomSerializer(room).data,
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
        serializer = RoomSerializer(rooms, many=True)
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
        packs = SongPack.objects.all()
        serializer = SongPackListSerializer(packs, many=True, context={'request': request, 'room': room})
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
        pack = get_object_or_404(SongPack, id=pack_id)
        serializer = SongPackDetailSerializer(pack, context={'request': request, 'room': room})
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

        if RoomPack.objects.filter(room=room, pack=pack).exists():
            serializer = SongPackDetailSerializer(pack, context={'request': request, 'room': room})
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
            serializer = SongPackDetailSerializer(pack, context={'request': request, 'room': room})
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

        serializer = SongPackDetailSerializer(pack, context={'request': request, 'room': room})
        return Response({
            'pack': serializer.data,
            'coins': request.user.coins,
            'message': 'Pack purchased successfully'
        }, status=status.HTTP_200_OK)


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
        packs = SongPack.objects.filter(room_purchases__room=room).distinct()
        serializer = SongPackListSerializer(packs, many=True, context={'request': request, 'room': room})
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

        if not RoomPack.objects.filter(room=room, pack=pack).exists():
            return Response({'error': 'This pack is not owned by the room'}, status=status.HTTP_403_FORBIDDEN)

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

        session.current_stage += 1
        if session.current_stage > len(PACK_BUNDLE_STAGE_ORDER):
            session.completed_at = timezone.now()
        session.save(update_fields=['current_stage', 'completed_at'])

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
        already_attempted = PackBundleAttempt.objects.filter(
            session=session,
            pack_track=current_pack_track,
            stage=session.current_stage
        ).exists()
        if already_attempted:
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

        # Advance stage or complete on correct guess
        if is_correct:
            session.current_stage = stage_guessed + 1
            session.completed_at = timezone.now()
        else:
            session.current_stage += 1
            if session.current_stage > len(PACK_BUNDLE_STAGE_ORDER):
                session.completed_at = timezone.now()

        session.save(update_fields=['points_earned', 'current_stage', 'completed_at'])

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
        }, status=status.HTTP_200_OK)


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

        if not RoomPack.objects.filter(room=room, pack=pack).exists():
            return Response({'error': 'This pack is not owned by the room'}, status=status.HTTP_403_FORBIDDEN)

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

        if not RoomPack.objects.filter(room=room, pack=pack).exists():
            return Response({'error': 'This pack is not owned by the room'}, status=status.HTTP_403_FORBIDDEN)

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

        if not RoomPack.objects.filter(room=room, pack=pack).exists():
            return Response({'error': 'This pack is not owned by the room'}, status=status.HTTP_403_FORBIDDEN)

        daily_track = _get_daily_pack_track(room, pack, today)
        if not daily_track:
            return Response({'error': 'Pack has no tracks'}, status=status.HTTP_404_NOT_FOUND)

        serializer = PostMessageSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        message = PackBundleMessage.objects.create(
            room=room,
            pack=pack,
            pack_daily_track=daily_track,
            user=request.user,
            message=serializer.validated_data['message']
        )

        response_serializer = PackBundleMessageSerializer(message)
        return Response(response_serializer.data, status=status.HTTP_201_CREATED)


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

        # Check if user is in the room
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({
                'error': 'You must be in the room to see the daily song'
            }, status=status.HTTP_403_FORBIDDEN)

        # Check if today's song already exists
        daily_song = DailySong.objects.filter(room=room, date=today).first()

        if daily_song:
            # Return existing song
            serializer = TrackSerializer(daily_song.track)
            return Response({
                'track': serializer.data,
                'date': today,
                'message': 'Today\'s song'
            }, status=status.HTTP_200_OK)

        # No song for today - select a random one
        # Get all tracks not used in this room yet
        used_track_ids = DailySong.objects.filter(room=room).values_list('track_id', flat=True)
        available_tracks = Track.objects.exclude(id__in=used_track_ids)

        # If all tracks have been used, allow reusing tracks
        if not available_tracks.exists():
            available_tracks = Track.objects.all()

        if not available_tracks.exists():
            return Response({
                'error': 'No tracks available. Please populate tracks using: python manage.py fetch_deezer_tracks'
            }, status=status.HTTP_404_NOT_FOUND)

        # Select random track
        track = random.choice(available_tracks)

        # Create daily song entry
        DailySong.objects.create(room=room, track=track, date=today)

        serializer = TrackSerializer(track)
        return Response({
            'track': serializer.data,
            'date': today,
            'message': 'New song selected for today'
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

        # Check if user is in the room
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({
                'error': 'You must be in the room to play the game'
            }, status=status.HTTP_403_FORBIDDEN)

        # Get or create today's song
        daily_song = DailySong.objects.filter(room=room, date=today).first()

        if not daily_song:
            # Select random track for today
            # Prefer tracks with deezer_id for fresh preview URLs
            used_track_ids = DailySong.objects.filter(room=room).values_list('track_id', flat=True)

            # First try to get tracks with deezer_id
            available_tracks = Track.objects.filter(deezer_id__isnull=False).exclude(id__in=used_track_ids)

            # If no unused tracks with deezer_id, use any track with deezer_id
            if not available_tracks.exists():
                available_tracks = Track.objects.filter(deezer_id__isnull=False)

            # If still no tracks with deezer_id, fall back to any track
            if not available_tracks.exists():
                available_tracks = Track.objects.exclude(id__in=used_track_ids)

            if not available_tracks.exists():
                available_tracks = Track.objects.all()

            if not available_tracks.exists():
                return Response({
                    'error': 'No tracks available. Please populate tracks using: python manage.py fetch_deezer_tracks'
                }, status=status.HTTP_404_NOT_FOUND)

            track = random.choice(available_tracks)
            daily_song = DailySong.objects.create(room=room, track=track, date=today)

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

        # Check if user is in the room
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({
                'error': 'You must be in the room to play the game'
            }, status=status.HTTP_403_FORBIDDEN)

        # Get today's song and user's session
        daily_song = DailySong.objects.filter(room=room, date=today).first()
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
        if game_session.completed_at:
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

        # Check if user is in the room
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({
                'error': 'You must be in the room to play the game'
            }, status=status.HTTP_403_FORBIDDEN)

        # Validate input
        serializer = SubmitGuessSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        guessed_track_id = serializer.validated_data['track_id']

        # Get today's song and user's session
        daily_song = DailySong.objects.filter(room=room, date=today).first()
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
        if game_session.completed_at:
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

            return Response({
                'is_correct': False,
                'current_snippet': game_session.current_snippet,
                'game_over': False,
                'message': f'Incorrect. Try again with snippet {game_session.current_snippet}',
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

        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response(
                {'error': 'You must be in the room to play the game'},
                status=status.HTTP_403_FORBIDDEN,
            )

        serializer = DailyGameRetrySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        action = serializer.validated_data['action']

        daily_song = DailySong.objects.filter(room=room, date=today).first()
        if not daily_song:
            return Response({'error': 'No song available for today'}, status=status.HTTP_404_NOT_FOUND)

        game_session = DailyGameSession.objects.filter(
            room=room,
            user=request.user,
            daily_song=daily_song,
        ).first()
        if not game_session:
            return Response(
                {'error': 'No active game session. Start by calling GET /daily-game/'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if game_session.completed_at:
            return Response(
                {'error': 'Game already completed'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if game_session.current_snippet < MAX_DAILY_SNIPPET:
            return Response(
                {'error': 'Retry is only available after reaching the last snippet'},
                status=status.HTTP_400_BAD_REQUEST,
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
            return Response(
                {
                    'error': 'A retry is already active',
                    'current_snippet': game_session.current_snippet,
                    **_retry_state_payload(game_session),
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        if not game_session.awaiting_retry_unlock:
            return Response(
                {
                    'error': 'No retry is pending unlock yet',
                    'current_snippet': game_session.current_snippet,
                    **_retry_state_payload(game_session),
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        expected_action = _next_retry_requirement(game_session)
        if expected_action is None:
            return Response(
                {'error': 'No retries remaining', **_retry_state_payload(game_session)},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if action != expected_action:
            return Response(
                {
                    'error': f'Invalid retry action. Expected "{expected_action}"',
                    'expected_action': expected_action,
                    **_retry_state_payload(game_session),
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        with transaction.atomic():
            if action == 'coins':
                retry_cost = _daily_game_retry_coin_cost()
                if request.user.coins < retry_cost:
                    return Response(
                        {
                            'error': 'Insufficient coins',
                            'coins': request.user.coins,
                            'retry_cost_coins': retry_cost,
                            **_retry_state_payload(game_session),
                        },
                        status=status.HTTP_400_BAD_REQUEST,
                    )

                if not request.user.spend_coins(retry_cost, reason=f"Daily retry in room {room.room_code}"):
                    return Response(
                        {'error': 'Insufficient coins'},
                        status=status.HTTP_400_BAD_REQUEST,
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

        # Check if user is in the room
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({
                'error': 'You must be in the room to view the leaderboard'
            }, status=status.HTTP_403_FORBIDDEN)

        # Get today's song
        daily_song = DailySong.objects.filter(room=room, date=today).first()
        if not daily_song:
            return Response({
                'error': 'No song available for today'
            }, status=status.HTTP_404_NOT_FOUND)

        # Get completed sessions ordered by points and completion time
        sessions = DailyGameSession.objects.filter(
            room=room,
            daily_song=daily_song,
            correct_guess=True
        ).select_related('user').order_by('-points_earned', 'completed_at')

        # Build leaderboard entries
        leaderboard = []
        for session in sessions:
            leaderboard.append({
                'user': {
                    'id': str(session.user.id),
                    'username': session.user.username,
                    'email': session.user.email
                },
                'points_earned': session.points_earned,
                'snippet_number': session.current_snippet,
                'completed_at': session.completed_at
            })

        return Response({
            'date': today,
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

        # Check if user is in the room
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({
                'error': 'You must be in the room to view messages'
            }, status=status.HTTP_403_FORBIDDEN)

        # Get pagination parameters
        limit = int(request.query_params.get('limit', 50))
        offset = int(request.query_params.get('offset', 0))

        # Limit max to 100 messages per request
        limit = min(limit, 100)

        # Get messages for today only (daily-scoped chat)
        today = _active_game_date()
        messages = RoomMessage.objects.filter(room=room, created_at__date=today).select_related('user')[offset:offset + limit]

        serializer = RoomMessageSerializer(messages, many=True)
        return Response({
            'messages': serializer.data,
            'limit': limit,
            'offset': offset
        }, status=status.HTTP_200_OK)

    def post(self, request, room_id):
        room = get_object_or_404(Room, id=room_id)

        # Check if user is in the room
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({
                'error': 'You must be in the room to post messages'
            }, status=status.HTTP_403_FORBIDDEN)

        # Validate message
        serializer = PostMessageSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        # Create message
        message = RoomMessage.objects.create(
            room=room,
            user=request.user,
            message=serializer.validated_data['message']
        )

        response_serializer = RoomMessageSerializer(message)
        return Response(response_serializer.data, status=status.HTTP_201_CREATED)


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

        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({'error': 'You must be in the room to use hints'}, status=status.HTTP_403_FORBIDDEN)

        hint_type = request.data.get('hint_type', '').strip()
        if hint_type not in HINT_COSTS:
            return Response(
                {'error': f'Invalid hint_type. Must be one of: {", ".join(HINT_COSTS.keys())}'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        daily_song = DailySong.objects.filter(room=room, date=today).select_related('track').first()
        if not daily_song:
            return Response({'error': 'No song available for today'}, status=status.HTTP_404_NOT_FOUND)

        game_session = DailyGameSession.objects.filter(
            room=room, user=request.user, daily_song=daily_song
        ).first()
        if not game_session:
            return Response({'error': 'No active game session.'}, status=status.HTTP_400_BAD_REQUEST)

        if game_session.completed_at:
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

        if not query:
            return Response([], status=status.HTTP_200_OK)

        # Search tracks by title or artist (case-insensitive)
        tracks = Track.objects.filter(
            Q(title__icontains=query) | Q(artist__icontains=query)
        )[:10]  # Limit to 10 results

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

        limit = min(int(request.query_params.get('limit', 30)), 100)
        offset = int(request.query_params.get('offset', 0))

        daily_songs = DailySong.objects.filter(
            room=room,
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

        room = get_object_or_404(Room, id=room_id)
        if not RoomUser.objects.filter(room=room, user=request.user).exists():
            return Response({'error': 'You must be in the room to view history'}, status=status.HTTP_403_FORBIDDEN)

        if parsed_date >= _active_game_date():
            return Response({'error': 'This date is not yet in history.'}, status=status.HTTP_400_BAD_REQUEST)

        daily_song = DailySong.objects.filter(room=room, date=parsed_date).select_related('track').first()
        if not daily_song:
            return Response({'error': 'No song found for this date.'}, status=status.HTTP_404_NOT_FOUND)

        session = DailyGameSession.objects.filter(
            room=room, user=request.user, daily_song=daily_song
        ).first()

        leaderboard_sessions = DailyGameSession.objects.filter(
            room=room,
            daily_song=daily_song,
            correct_guess=True,
        ).select_related('user').order_by('-points_earned', 'completed_at')

        leaderboard = [
            {
                'user': {'id': str(s.user.id), 'username': s.user.username},
                'points_earned': s.points_earned,
                'snippet_number': s.current_snippet,
                'completed_at': s.completed_at.isoformat() if s.completed_at else None,
            }
            for s in leaderboard_sessions
        ]

        messages = RoomMessage.objects.filter(
            room=room,
            created_at__date=parsed_date,
        ).select_related('user').order_by('created_at')

        return Response({
            'date': parsed_date.isoformat(),
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
