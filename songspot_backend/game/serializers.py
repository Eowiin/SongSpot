from django.contrib.auth import get_user_model
from rest_framework import serializers
from .models import Track, GameScore, UserBest

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
