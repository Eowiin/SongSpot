import random
from datetime import timedelta

from django.db import transaction
from django.db.models import Count, Q, Subquery, OuterRef
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from songspot.throttling import GameSearchThrottle

from .models import (
    Track, GameScore, UserBest, FavouriteArtist,
    CATEGORY_CHOICES,
)
from .serializers import (
    TrackSerializer,
    TrackSearchSerializer,
    GameScoreSubmitSerializer,
    GameScoreSerializer,
    UserBestSerializer,
    LeaderboardEntrySerializer,
    MigrateGuestStatsSerializer,
)

GENRE_DISPLAY = dict(CATEGORY_CHOICES)


class CategoryListView(APIView):
    """
    List available genres derived directly from tracks in the library.
    Returns one entry per genre key — no more multiple packs per genre.
    """
    permission_classes = [AllowAny]

    def get(self, request):
        rows = (
            Track.objects
            .filter(preview_url__isnull=False)
            .exclude(preview_url='')
            .exclude(genre__isnull=True)
            .exclude(genre='')
            .values('genre')
            .annotate(track_count=Count('id'))
            .order_by('genre')
        )
        result = [
            {
                'id': row['genre'],
                'name': GENRE_DISPLAY.get(row['genre'], row['genre'].replace('_', ' ').title()),
                'category': row['genre'],
                'track_count': row['track_count'],
            }
            for row in rows
        ]
        return Response(result)


class NextSongView(APIView):
    """
    Return a random track for the current session.

    Query params:
      genre   — genre key (e.g. 'pop', 'hiphop')
      artist  — artist name filter (case-insensitive)
      exclude — comma-separated track UUIDs already seen this session
    """
    permission_classes = [AllowAny]
    throttle_classes = [GameSearchThrottle]

    def get(self, request):
        genre = request.query_params.get('genre', '').strip()
        artist = request.query_params.get('artist', '').strip()
        exclude_raw = request.query_params.get('exclude', '')
        exclude_ids = [e.strip() for e in exclude_raw.split(',') if e.strip()]

        qs = Track.objects.filter(preview_url__isnull=False).exclude(preview_url='')

        if genre:
            qs = qs.filter(genre=genre)
        elif artist:
            qs = qs.filter(artist__icontains=artist)

        if exclude_ids:
            qs = qs.exclude(id__in=exclude_ids)

        count = qs.count()
        if count == 0:
            return Response({'detail': 'No tracks available.'}, status=status.HTTP_404_NOT_FOUND)

        track = qs[random.randint(0, count - 1)]
        return Response(TrackSerializer(track).data)


def _artist_picture_subquery():
    """Subquery returning the first non-null artist_picture_url for a given artist name."""
    return Subquery(
        Track.objects.filter(
            artist=OuterRef('artist'),
            artist_picture_url__isnull=False,
        ).exclude(artist_picture_url='')
        .values('artist_picture_url')[:1]
    )


class ArtistListView(APIView):
    """Autocomplete artist search for the category select screen."""
    permission_classes = [AllowAny]

    def get(self, request):
        q = request.query_params.get('q', '').strip()
        if len(q) < 2:
            return Response([])
        artists = (
            Track.objects.filter(artist__icontains=q)
            .values('artist')
            .distinct()
            .order_by('artist')
            .annotate(picture_url=_artist_picture_subquery())[:30]
        )
        return Response([{'name': a['artist'], 'picture_url': a['picture_url']} for a in artists])


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
        pictures = {
            t['artist']: t['artist_picture_url']
            for t in Track.objects
            .filter(artist__in=artist_names, artist_picture_url__isnull=False)
            .exclude(artist_picture_url='')
            .values('artist', 'artist_picture_url')
        }
        return Response([{'name': n, 'picture_url': pictures.get(n)} for n in artist_names])


class FavouriteArtistView(APIView):
    """List and add favourite artists for the current user."""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        artist_names = list(
            FavouriteArtist.objects
            .filter(user=request.user)
            .values_list('artist_name', flat=True)
        )
        pictures = {
            t['artist']: t['artist_picture_url']
            for t in Track.objects
            .filter(artist__in=artist_names, artist_picture_url__isnull=False)
            .exclude(artist_picture_url='')
            .values('artist', 'artist_picture_url')
        }
        return Response([{'name': n, 'picture_url': pictures.get(n)} for n in artist_names])

    def post(self, request):
        artist_name = (request.data.get('artist_name') or '').strip()
        if not artist_name:
            return Response({'detail': 'artist_name is required.'}, status=status.HTTP_400_BAD_REQUEST)
        FavouriteArtist.objects.get_or_create(user=request.user, artist_name=artist_name)
        return Response({'artist_name': artist_name}, status=status.HTTP_201_CREATED)


class FavouriteArtistDetailView(APIView):
    """Remove a single favourite artist."""
    permission_classes = [IsAuthenticated]

    def delete(self, request, artist_name):
        FavouriteArtist.objects.filter(user=request.user, artist_name=artist_name).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class SearchTracksView(APIView):
    """Autocomplete track search for the guess input."""
    permission_classes = [AllowAny]
    throttle_classes = [GameSearchThrottle]

    def get(self, request):
        q = request.query_params.get('q', '').strip()
        if len(q) < 2:
            return Response([])
        tracks = (
            Track.objects.filter(
                Q(title__icontains=q) | Q(artist__icontains=q)
            )
            .order_by('title')[:20]
        )
        return Response(TrackSearchSerializer(tracks, many=True).data)


class TrackRefreshPreviewView(APIView):
    """Force-refresh a track's preview URL from Deezer."""
    permission_classes = [AllowAny]

    def post(self, request, track_id):
        try:
            track = Track.objects.get(id=track_id)
        except Track.DoesNotExist:
            return Response({'detail': 'Not found.'}, status=status.HTTP_404_NOT_FOUND)
        url = track.get_fresh_preview_url(force_refresh=True)
        return Response({'preview_url': url})


class SubmitScoreView(APIView):
    """Submit a completed session score. Creates GameScore and updates UserBest."""
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = GameScoreSubmitSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        with transaction.atomic():
            score = GameScore.objects.create(
                user=request.user,
                genre=data.get('genre') or None,
                artist_filter=data.get('artist_filter', ''),
                difficulty=data.get('difficulty', 'medium'),
                songs_played=data['songs_played'],
                songs_correct=data['songs_correct'],
                best_streak=data['best_streak'],
                total_score=data['total_score'],
            )
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
