from rest_framework import serializers
from django.contrib.auth import get_user_model
from .models import (
    Track, SongPack, PackTrack, Room, RoomUser,
    DailySong, DailyGameSession, GuessAttempt, RoomMessage
)

User = get_user_model()


class TrackSerializer(serializers.ModelSerializer):
    class Meta:
        model = Track
        fields = ('id', 'title', 'artist', 'preview_url', 'cover_url', 'created_at')
        read_only_fields = ('id', 'created_at')


class PackTrackSerializer(serializers.ModelSerializer):
    track = TrackSerializer(read_only=True)

    class Meta:
        model = PackTrack
        fields = ('track', 'order_in_pack')


class SongPackListSerializer(serializers.ModelSerializer):
    track_count = serializers.SerializerMethodField()

    class Meta:
        model = SongPack
        fields = ('id', 'name', 'description', 'icon_url', 'track_count', 'created_at')
        read_only_fields = ('id', 'created_at')

    def get_track_count(self, obj):
        return obj.pack_tracks.count()


class SongPackDetailSerializer(serializers.ModelSerializer):
    tracks = PackTrackSerializer(source='pack_tracks', many=True, read_only=True)
    track_count = serializers.SerializerMethodField()

    class Meta:
        model = SongPack
        fields = ('id', 'name', 'description', 'icon_url', 'track_count', 'tracks', 'created_at')
        read_only_fields = ('id', 'created_at')

    def get_track_count(self, obj):
        return obj.pack_tracks.count()


class UserBasicSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ('id', 'username', 'email')
        read_only_fields = ('id', 'username', 'email')


class RoomUserSerializer(serializers.ModelSerializer):
    user = UserBasicSerializer(read_only=True)

    class Meta:
        model = RoomUser
        fields = ('user', 'joined_at')
        read_only_fields = ('user', 'joined_at')


class RoomSerializer(serializers.ModelSerializer):
    host_user = UserBasicSerializer(read_only=True)
    users = RoomUserSerializer(source='room_users', many=True, read_only=True)
    user_count = serializers.SerializerMethodField()

    class Meta:
        model = Room
        fields = ('id', 'room_code', 'host_user', 'users', 'user_count', 'created_at')
        read_only_fields = ('id', 'room_code', 'host_user', 'created_at')

    def get_user_count(self, obj):
        return obj.room_users.count()


class RoomCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Room
        fields = []  # Room code is auto-generated, no input needed


class JoinRoomSerializer(serializers.Serializer):
    room_code = serializers.CharField(max_length=10)

    def validate_room_code(self, value):
        try:
            Room.objects.get(room_code=value.upper())
        except Room.DoesNotExist:
            raise serializers.ValidationError("Room not found.")
        return value.upper()


class DailySongSerializer(serializers.ModelSerializer):
    track = TrackSerializer(read_only=True)

    class Meta:
        model = DailySong
        fields = ('id', 'track', 'date', 'created_at')
        read_only_fields = ('id', 'date', 'created_at')


class GameSessionSerializer(serializers.ModelSerializer):
    daily_song = DailySongSerializer(read_only=True)
    user = UserBasicSerializer(read_only=True)

    class Meta:
        model = DailyGameSession
        fields = (
            'id', 'user', 'daily_song', 'current_snippet',
            'guesses_made', 'correct_guess', 'points_earned',
            'completed_at', 'created_at'
        )
        read_only_fields = (
            'id', 'user', 'daily_song', 'guesses_made',
            'correct_guess', 'points_earned', 'completed_at', 'created_at'
        )


class GuessAttemptSerializer(serializers.ModelSerializer):
    class Meta:
        model = GuessAttempt
        fields = (
            'id', 'snippet_number', 'guessed_title',
            'guessed_artist', 'is_correct', 'created_at'
        )
        read_only_fields = ('id', 'is_correct', 'created_at')


class SubmitGuessSerializer(serializers.Serializer):
    track_id = serializers.UUIDField(required=True)

    def validate_track_id(self, value):
        if not Track.objects.filter(id=value).exists():
            raise serializers.ValidationError("Track not found.")
        return value


class LeaderboardEntrySerializer(serializers.Serializer):
    user = UserBasicSerializer()
    points_earned = serializers.IntegerField()
    snippet_number = serializers.IntegerField()
    completed_at = serializers.DateTimeField()


class RoomMessageSerializer(serializers.ModelSerializer):
    user = UserBasicSerializer(read_only=True)

    class Meta:
        model = RoomMessage
        fields = ('id', 'user', 'message', 'created_at')
        read_only_fields = ('id', 'user', 'created_at')


class PostMessageSerializer(serializers.Serializer):
    message = serializers.CharField(max_length=500, required=True)

    def validate_message(self, value):
        if not value.strip():
            raise serializers.ValidationError("Message cannot be empty.")
        if len(value) > 500:
            raise serializers.ValidationError("Message cannot exceed 500 characters.")
        return value.strip()
