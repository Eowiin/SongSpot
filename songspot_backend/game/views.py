from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django.shortcuts import get_object_or_404
from django.utils import timezone
import random
from .models import (
    Track, SongPack, Room, RoomUser, DailySong,
    DailyGameSession, GuessAttempt, RoomMessage
)
from .serializers import (
    TrackSerializer,
    SongPackListSerializer,
    RoomSerializer,
    RoomCreateSerializer,
    JoinRoomSerializer,
    GameSessionSerializer,
    SubmitGuessSerializer,
    LeaderboardEntrySerializer,
    RoomMessageSerializer,
    PostMessageSerializer,
)

# Scoring constants
SNIPPET_POINTS = {
    1: 6,  # Guessed on 0.1s snippet
    2: 5,  # Guessed on 0.5s snippet
    3: 4,  # Guessed on 2s snippet
    4: 3,  # Guessed on 4s snippet
    5: 2,  # Guessed on 8s snippet
    6: 1,  # Guessed on 15s snippet
}


class RoomCreateView(APIView):
    """
    Create a new permanent game room with auto-generated code.

    POST /api/game/rooms/create/
    Headers: Authorization: Bearer <access_token>
    Body: {} (empty - room code is auto-generated)
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        # Check if user already has a room as host
        existing_room = Room.objects.filter(host_user=request.user).first()
        if existing_room:
            # User already has a room, return it
            response_serializer = RoomSerializer(existing_room)
            return Response({
                'room': response_serializer.data,
                'message': 'You already have a room'
            }, status=status.HTTP_200_OK)

        # Create new room with auto-generated code
        serializer = RoomCreateSerializer(data={})
        if serializer.is_valid():
            room = serializer.save(host_user=request.user)

            # Automatically add the host to the room
            RoomUser.objects.create(room=room, user=request.user)

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
        packs = SongPack.objects.all()
        serializer = SongPackListSerializer(packs, many=True)
        return Response(serializer.data, status=status.HTTP_200_OK)


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
        today = timezone.now().date()

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
        today = timezone.now().date()

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
            fresh_preview_url = daily_song.track.get_fresh_preview_url()
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
        today = timezone.now().date()

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
        if game_session.correct_guess:
            return Response({
                'error': 'You already guessed correctly',
                'current_snippet': game_session.current_snippet
            }, status=status.HTTP_400_BAD_REQUEST)

        # Check if already at max snippets
        if game_session.current_snippet >= 6:
            return Response({
                'error': 'Already at maximum snippet level',
                'current_snippet': 6
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
    """
    permission_classes = [IsAuthenticated]

    def post(self, request, room_id):
        room = get_object_or_404(Room, id=room_id)
        today = timezone.now().date()

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
        if game_session.correct_guess:
            return Response({
                'error': 'You already guessed correctly',
                'correct_answer': {
                    'title': daily_song.track.title,
                    'artist': daily_song.track.artist
                }
            }, status=status.HTTP_400_BAD_REQUEST)

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
            game_session.save()

            return Response({
                'is_correct': True,
                'points_earned': points,
                'snippet_number': game_session.current_snippet,
                'message': f'Correct! You earned {points} points!',
                'correct_answer': {
                    'title': daily_song.track.title,
                    'artist': daily_song.track.artist
                }
            }, status=status.HTTP_200_OK)
        else:
            # Incorrect guess - move to next snippet if not at max
            if game_session.current_snippet < 6:
                game_session.current_snippet += 1
                game_session.save()

                return Response({
                    'is_correct': False,
                    'current_snippet': game_session.current_snippet,
                    'message': f'Incorrect. Try again with snippet {game_session.current_snippet}'
                }, status=status.HTTP_200_OK)
            else:
                # Used all snippets - reveal answer with 0 points
                game_session.correct_guess = False
                game_session.points_earned = 0
                game_session.completed_at = timezone.now()
                game_session.save()

                return Response({
                    'is_correct': False,
                    'points_earned': 0,
                    'message': 'No more snippets. Better luck next time!',
                    'correct_answer': {
                        'title': daily_song.track.title,
                        'artist': daily_song.track.artist
                    }
                }, status=status.HTTP_200_OK)


class LeaderboardView(APIView):
    """
    Get today's leaderboard for a room.

    GET /api/game/rooms/<room_id>/daily-game/leaderboard/
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, room_id):
        room = get_object_or_404(Room, id=room_id)
        today = timezone.now().date()

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
    """
    permission_classes = [IsAuthenticated]

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

        # Get messages
        messages = RoomMessage.objects.filter(room=room).select_related('user')[offset:offset + limit]

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


class SearchTracksView(APIView):
    """
    Search for tracks by title or artist.

    GET /api/game/tracks/search/?q=search_query
    Headers: Authorization: Bearer <access_token>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        from django.db.models import Q

        query = request.query_params.get('q', '').strip()

        if not query:
            return Response([], status=status.HTTP_200_OK)

        # Search tracks by title or artist (case-insensitive)
        tracks = Track.objects.filter(
            Q(title__icontains=query) | Q(artist__icontains=query)
        )[:10]  # Limit to 10 results

        serializer = TrackSerializer(tracks, many=True)
        return Response(serializer.data, status=status.HTTP_200_OK)
