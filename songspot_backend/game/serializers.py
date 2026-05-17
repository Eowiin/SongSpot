from django.contrib.auth import get_user_model
from rest_framework import serializers
from .models import Track, GameScore, UserBest, UserElo, DuelMatch, DuelRound

User = get_user_model()


class TrackSerializer(serializers.ModelSerializer):
    class Meta:
        model = Track
        fields = ('id', 'title', 'artist', 'preview_url', 'cover_url', 'release_year', 'genre')
        read_only_fields = fields


class TrackSearchSerializer(serializers.ModelSerializer):
    """Lightweight serializer for autocomplete search — no preview URL."""
    class Meta:
        model = Track
        fields = ('id', 'title', 'artist', 'cover_url')
        read_only_fields = fields


class GameScoreSubmitSerializer(serializers.Serializer):
    genre = serializers.CharField(required=False, allow_blank=True, default='')
    artist_filter = serializers.CharField(required=False, allow_blank=True, default='')
    difficulty = serializers.ChoiceField(choices=['easy', 'medium', 'hard'], default='medium')
    songs_played = serializers.IntegerField(min_value=0)
    songs_correct = serializers.IntegerField(min_value=0)
    best_streak = serializers.IntegerField(min_value=0)
    total_score = serializers.IntegerField(min_value=0)


class GameScoreSerializer(serializers.ModelSerializer):
    class Meta:
        model = GameScore
        fields = (
            'id', 'genre', 'artist_filter', 'difficulty',
            'songs_played', 'songs_correct', 'best_streak', 'total_score', 'played_at',
        )
        read_only_fields = fields


class UserBestSerializer(serializers.ModelSerializer):
    per_genre = serializers.JSONField()

    class Meta:
        model = UserBest
        fields = (
            'best_score_overall', 'best_streak_overall',
            'total_songs_played', 'total_songs_correct', 'per_genre',
        )
        read_only_fields = fields


class MigrateGuestStatsSerializer(serializers.Serializer):
    best_score = serializers.IntegerField(min_value=0)
    best_streak = serializers.IntegerField(min_value=0)
    songs_played = serializers.IntegerField(min_value=0)
    songs_correct = serializers.IntegerField(min_value=0)


class LeaderboardUserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ('id', 'username')
        read_only_fields = fields


class LeaderboardEntrySerializer(serializers.ModelSerializer):
    user = LeaderboardUserSerializer(read_only=True)

    class Meta:
        model = GameScore
        fields = (
            'id', 'user', 'genre', 'artist_filter',
            'total_score', 'best_streak', 'songs_played', 'songs_correct', 'played_at',
        )
        read_only_fields = fields


# ── Duel serializers ──────────────────────────────────────────────────────────

class UserEloSerializer(serializers.ModelSerializer):
    rank = serializers.SerializerMethodField()

    class Meta:
        model = UserElo
        fields = ('elo', 'wins', 'losses', 'draws', 'rank')
        read_only_fields = fields

    def get_rank(self, obj):
        return UserElo.objects.filter(elo__gt=obj.elo).count() + 1


class DuelRoundSerializer(serializers.ModelSerializer):
    track_title = serializers.CharField(source='track.title', read_only=True)
    track_artist = serializers.CharField(source='track.artist', read_only=True)
    track_cover = serializers.URLField(source='track.cover_url', read_only=True)

    class Meta:
        model = DuelRound
        fields = (
            'round_number',
            'track_title', 'track_artist', 'track_cover',
            'player1_correct', 'player1_points', 'player1_snippets_used',
            'player2_correct', 'player2_points', 'player2_snippets_used',
        )
        read_only_fields = fields


class DuelMatchSerializer(serializers.ModelSerializer):
    player1_username = serializers.CharField(source='player1.username', read_only=True)
    player2_username = serializers.CharField(source='player2.username', read_only=True)
    playlist_name = serializers.CharField(source='playlist.name', read_only=True, default=None)
    rounds = DuelRoundSerializer(many=True, read_only=True)

    class Meta:
        model = DuelMatch
        fields = (
            'id', 'status',
            'player1_username', 'player2_username',
            'playlist_name',
            'total_rounds', 'current_round',
            'player1_score', 'player2_score',
            'rounds',
            'created_at', 'updated_at',
        )
        read_only_fields = fields


class DuelLeaderboardEntrySerializer(serializers.ModelSerializer):
    username = serializers.CharField(source='user.username', read_only=True)
    rank = serializers.SerializerMethodField()

    class Meta:
        model = UserElo
        fields = ('username', 'elo', 'wins', 'losses', 'draws', 'rank')
        read_only_fields = fields

    def get_rank(self, obj):
        return self.context.get('ranks', {}).get(obj.user_id, 0)
