from django.conf import settings
from rest_framework import serializers
from django.contrib.auth import get_user_model
from .models import (
    Track, SongPack, PackTrack, Room, RoomUser, RoomPack,
    DailySong, PackDailyTrack, PackBundleSession, PackBundleAttempt,
    DailyGameSession, GuessAttempt, RoomMessage, PackBundleMessage,
    RoomDailyModeState,
)
from .daily_modes import serialize_room_daily_modes

User = get_user_model()


class TrackSerializer(serializers.ModelSerializer):
    class Meta:
        model = Track
        fields = ('id', 'title', 'artist', 'preview_url', 'cover_url', 'created_at')
        read_only_fields = ('id', 'created_at')


class PackTrackSerializer(serializers.ModelSerializer):
    track = TrackSerializer(read_only=True)
    # Stems are stored on Track (not PackTrack) so one song can appear in
    # multiple packs without regenerating stems. We expose them at the same
    # top-level keys to keep the API shape unchanged for mobile clients.
    vocals_url = serializers.SerializerMethodField()
    drums_url = serializers.SerializerMethodField()
    bass_url = serializers.SerializerMethodField()
    other_url = serializers.SerializerMethodField()

    class Meta:
        model = PackTrack
        fields = (
            'track',
            'order_in_pack',
            'vocals_url',
            'drums_url',
            'bass_url',
            'other_url',
        )

    def get_vocals_url(self, obj):
        return obj.track.vocals_url

    def get_drums_url(self, obj):
        return obj.track.drums_url

    def get_bass_url(self, obj):
        return obj.track.bass_url

    def get_other_url(self, obj):
        return obj.track.other_url


class SongPackListSerializer(serializers.ModelSerializer):
    track_count = serializers.SerializerMethodField()
    is_owned = serializers.SerializerMethodField()
    is_active = serializers.SerializerMethodField()
    is_completed = serializers.SerializerMethodField()
    can_activate = serializers.SerializerMethodField()
    activated_on = serializers.SerializerMethodField()
    completed_on = serializers.SerializerMethodField()
    total_days = serializers.SerializerMethodField()
    current_day = serializers.SerializerMethodField()
    remaining_days = serializers.SerializerMethodField()

    class Meta:
        model = SongPack
        fields = (
            'id', 'name', 'description', 'icon_url', 'track_count',
            'category', 'price_coins', 'is_free', 'auto_unlock',
            'is_owned', 'is_active', 'is_completed', 'can_activate',
            'activated_on', 'completed_on', 'total_days', 'current_day',
            'remaining_days', 'created_at',
        )
        read_only_fields = ('id', 'created_at')

    def get_track_count(self, obj):
        return obj.pack_tracks.count()

    def get_is_owned(self, obj):
        request = self.context.get('request')
        room = self.context.get('room')
        if not request or not request.user.is_authenticated or not room:
            return False
        return RoomPack.objects.filter(room=room, pack=obj).exists()

    def _room_pack(self, obj):
        room = self.context.get('room')
        if not room:
            return None
        return RoomPack.objects.filter(room=room, pack=obj).first()

    def _today(self):
        return self.context.get('active_game_date')

    def get_is_active(self, obj):
        room_pack = self._room_pack(obj)
        return bool(room_pack and room_pack.is_active)

    def get_is_completed(self, obj):
        room_pack = self._room_pack(obj)
        return bool(room_pack and room_pack.completed_on)

    def get_can_activate(self, obj):
        room = self.context.get('room')
        room_pack = self._room_pack(obj)
        if not room or not room_pack or room_pack.completed_on:
            return False
        if room_pack.is_active:
            return False
        if obj.pack_tracks.count() == 0:
            return False
        return not RoomPack.objects.filter(room=room, is_active=True).exclude(id=room_pack.id).exists()

    def get_activated_on(self, obj):
        room_pack = self._room_pack(obj)
        return room_pack.activated_on if room_pack else None

    def get_completed_on(self, obj):
        room_pack = self._room_pack(obj)
        return room_pack.completed_on if room_pack else None

    def get_total_days(self, obj):
        room_pack = self._room_pack(obj)
        if not room_pack:
            return obj.pack_tracks.count()
        return room_pack.total_days

    def get_current_day(self, obj):
        room_pack = self._room_pack(obj)
        if not room_pack or not room_pack.activated_on:
            return None
        return room_pack.current_day(self._today())

    def get_remaining_days(self, obj):
        room_pack = self._room_pack(obj)
        if not room_pack or not room_pack.activated_on:
            return None
        return room_pack.remaining_days(self._today())


class SongPackDetailSerializer(serializers.ModelSerializer):
    track_count = serializers.SerializerMethodField()
    is_owned = serializers.SerializerMethodField()
    is_active = serializers.SerializerMethodField()
    is_completed = serializers.SerializerMethodField()
    can_activate = serializers.SerializerMethodField()
    activated_on = serializers.SerializerMethodField()
    completed_on = serializers.SerializerMethodField()
    total_days = serializers.SerializerMethodField()
    current_day = serializers.SerializerMethodField()
    remaining_days = serializers.SerializerMethodField()

    class Meta:
        model = SongPack
        fields = (
            'id', 'name', 'description', 'icon_url', 'track_count',
            'category', 'price_coins', 'is_free', 'auto_unlock',
            'is_owned', 'is_active', 'is_completed', 'can_activate',
            'activated_on', 'completed_on', 'total_days', 'current_day',
            'remaining_days', 'created_at',
        )
        read_only_fields = ('id', 'created_at')

    def get_track_count(self, obj):
        return obj.pack_tracks.count()

    def get_is_owned(self, obj):
        request = self.context.get('request')
        room = self.context.get('room')
        if not request or not request.user.is_authenticated or not room:
            return False
        return RoomPack.objects.filter(room=room, pack=obj).exists()

    def _room_pack(self, obj):
        room = self.context.get('room')
        if not room:
            return None
        return RoomPack.objects.filter(room=room, pack=obj).first()

    def _today(self):
        return self.context.get('active_game_date')

    def get_is_active(self, obj):
        room_pack = self._room_pack(obj)
        return bool(room_pack and room_pack.is_active)

    def get_is_completed(self, obj):
        room_pack = self._room_pack(obj)
        return bool(room_pack and room_pack.completed_on)

    def get_can_activate(self, obj):
        room = self.context.get('room')
        room_pack = self._room_pack(obj)
        if not room or not room_pack or room_pack.completed_on:
            return False
        if room_pack.is_active:
            return False
        if obj.pack_tracks.count() == 0:
            return False
        return not RoomPack.objects.filter(room=room, is_active=True).exclude(id=room_pack.id).exists()

    def get_activated_on(self, obj):
        room_pack = self._room_pack(obj)
        return room_pack.activated_on if room_pack else None

    def get_completed_on(self, obj):
        room_pack = self._room_pack(obj)
        return room_pack.completed_on if room_pack else None

    def get_total_days(self, obj):
        room_pack = self._room_pack(obj)
        if not room_pack:
            return obj.pack_tracks.count()
        return room_pack.total_days

    def get_current_day(self, obj):
        room_pack = self._room_pack(obj)
        if not room_pack or not room_pack.activated_on:
            return None
        return room_pack.current_day(self._today())

    def get_remaining_days(self, obj):
        room_pack = self._room_pack(obj)
        if not room_pack or not room_pack.activated_on:
            return None
        return room_pack.remaining_days(self._today())


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
    active_pack = serializers.SerializerMethodField()
    daily_modes = serializers.SerializerMethodField()

    class Meta:
        model = Room
        fields = (
            'id',
            'room_code',
            'name',
            'host_user',
            'users',
            'user_count',
            'active_pack',
            'daily_modes',
            'created_at',
        )
        read_only_fields = ('id', 'room_code', 'host_user', 'created_at')

    def get_user_count(self, obj):
        return obj.room_users.count()

    def get_active_pack(self, obj):
        request = self.context.get('request')
        room_pack = RoomPack.objects.filter(room=obj, is_active=True).select_related('pack').first()
        if not room_pack:
            return None
        serializer = SongPackListSerializer(
            room_pack.pack,
            context={
                'request': request,
                'room': obj,
                'active_game_date': self.context.get('active_game_date'),
            },
        )
        return serializer.data

    def get_daily_modes(self, obj):
        active_game_date = self.context.get('active_game_date')
        return serialize_room_daily_modes(obj, active_game_date)


class RoomCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Room
        fields = ['name']  # Optional name, room code is auto-generated


class RoomRenameSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=50, required=False, allow_blank=True)

    def validate_name(self, value):
        if value:
            value = value.strip()
            if len(value) > 50:
                raise serializers.ValidationError("Room name cannot exceed 50 characters.")
        return value if value else None


class JoinRoomSerializer(serializers.Serializer):
    room_code = serializers.CharField(max_length=10)

    def validate_room_code(self, value):
        try:
            Room.objects.get(room_code=value.upper())
        except Room.DoesNotExist:
            raise serializers.ValidationError("Room not found.")
        return value.upper()


class RoomDailyModeContributionSerializer(serializers.Serializer):
    mode = serializers.ChoiceField(
        choices=tuple(
            choice for choice in RoomDailyModeState._meta.get_field('mode').choices
        )
    )
    amount = serializers.IntegerField(min_value=1)


class DailySongSerializer(serializers.ModelSerializer):
    track = TrackSerializer(read_only=True)

    class Meta:
        model = DailySong
        fields = (
            'id',
            'track',
            'mode',
            'genre_key',
            'genre_name',
            'date',
            'created_at',
        )
        read_only_fields = ('id', 'mode', 'genre_key', 'genre_name', 'date', 'created_at')


class GameSessionSerializer(serializers.ModelSerializer):
    daily_song = DailySongSerializer(read_only=True)
    user = UserBasicSerializer(read_only=True)
    retry_available = serializers.SerializerMethodField()
    next_retry_requirement = serializers.SerializerMethodField()
    retry_cost_coins = serializers.SerializerMethodField()

    class Meta:
        model = DailyGameSession
        fields = (
            'id', 'user', 'daily_song', 'current_snippet',
            'guesses_made', 'retries_used', 'retry_credits',
            'awaiting_retry_unlock',
            'retry_available', 'next_retry_requirement', 'retry_cost_coins',
            'correct_guess', 'points_earned', 'completed_at', 'created_at',
            'hints_used'
        )
        read_only_fields = (
            'id', 'user', 'daily_song', 'guesses_made',
            'retries_used', 'retry_credits',
            'awaiting_retry_unlock',
            'retry_available', 'next_retry_requirement', 'retry_cost_coins',
            'correct_guess', 'points_earned', 'completed_at', 'created_at',
            'hints_used'
        )

    def get_retry_available(self, obj):
        if obj.completed_at or obj.correct_guess:
            return False
        if obj.current_snippet < 6:
            return False
        if obj.retry_credits > 0:
            return True
        if not obj.awaiting_retry_unlock:
            return False
        max_retries = int(getattr(settings, 'DAILY_GAME_MAX_RETRIES', 2))
        return obj.retries_used < max_retries

    def get_next_retry_requirement(self, obj):
        if obj.completed_at or obj.correct_guess:
            return None
        if obj.current_snippet < 6:
            return None
        if obj.retry_credits > 0:
            return None
        if not obj.awaiting_retry_unlock:
            return None
        max_retries = int(getattr(settings, 'DAILY_GAME_MAX_RETRIES', 2))
        if obj.retries_used >= max_retries:
            return None
        return 'ad' if obj.retries_used == 0 else 'coins'

    def get_retry_cost_coins(self, obj):
        return int(getattr(settings, 'DAILY_GAME_RETRY_COIN_COST', 120))


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


class DailyGameRetrySerializer(serializers.Serializer):
    action = serializers.ChoiceField(choices=['ad', 'coins', 'forfeit'])


class PackBundleSessionSerializer(serializers.ModelSerializer):
    pack_track = serializers.SerializerMethodField()
    date = serializers.DateField(source='pack_daily_track.date', read_only=True)
    retry_available = serializers.SerializerMethodField()
    next_retry_requirement = serializers.SerializerMethodField()
    retry_cost_coins = serializers.SerializerMethodField()

    class Meta:
        model = PackBundleSession
        fields = (
            'id',
            'current_stage',
            'retries_used',
            'retry_credits',
            'awaiting_retry_unlock',
            'retry_available',
            'next_retry_requirement',
            'retry_cost_coins',
            'points_earned',
            'completed_at',
            'created_at',
            'date',
            'pack_track',
            'hints_used',
        )
        read_only_fields = (
            'id',
            'retries_used',
            'retry_credits',
            'awaiting_retry_unlock',
            'retry_available',
            'next_retry_requirement',
            'retry_cost_coins',
            'points_earned',
            'completed_at',
            'created_at',
            'date',
            'pack_track',
            'hints_used',
        )

    def get_pack_track(self, obj):
        if not obj.pack_daily_track:
            return None
        pack_track = PackTrack.objects.filter(
            pack=obj.pack,
            track=obj.pack_daily_track.track
        ).first()
        if not pack_track:
            return None
        return PackTrackSerializer(pack_track).data

    def get_retry_available(self, obj):
        if obj.retry_credits > 0:
            return True
        if not obj.awaiting_retry_unlock:
            return False
        return self.get_next_retry_requirement(obj) is not None

    def get_next_retry_requirement(self, obj):
        if obj.retry_credits > 0:
            return None
        if not obj.awaiting_retry_unlock:
            return None
        max_retries = max(0, int(getattr(settings, 'DAILY_GAME_MAX_RETRIES', 2)))
        if obj.retries_used >= max_retries:
            return None
        return 'ad' if obj.retries_used == 0 else 'coins'

    def get_retry_cost_coins(self, obj):
        return max(0, int(getattr(settings, 'DAILY_GAME_RETRY_COIN_COST', 120)))


class PackBundleGuessSerializer(serializers.Serializer):
    track_id = serializers.UUIDField(required=True)

    def validate_track_id(self, value):
        if not Track.objects.filter(id=value).exists():
            raise serializers.ValidationError("Track not found.")
        return value


class RoomMessageSerializer(serializers.ModelSerializer):
    user = UserBasicSerializer(read_only=True)

    class Meta:
        model = RoomMessage
        fields = ('id', 'user', 'message', 'client_message_id', 'created_at')
        read_only_fields = ('id', 'user', 'created_at')


class PackBundleMessageSerializer(serializers.ModelSerializer):
    user = UserBasicSerializer(read_only=True)

    class Meta:
        model = PackBundleMessage
        fields = ('id', 'user', 'message', 'client_message_id', 'created_at')
        read_only_fields = ('id', 'user', 'created_at')


class PostMessageSerializer(serializers.Serializer):
    message = serializers.CharField(max_length=500, required=True)
    client_message_id = serializers.CharField(
        max_length=64,
        required=False,
        allow_blank=False,
    )

    def validate_message(self, value):
        if not value.strip():
            raise serializers.ValidationError("Message cannot be empty.")
        if len(value) > 500:
            raise serializers.ValidationError("Message cannot exceed 500 characters.")
        return value.strip()

    def validate_client_message_id(self, value):
        cleaned = value.strip()
        if not cleaned:
            raise serializers.ValidationError("Client message ID cannot be empty.")
        return cleaned


class RoomBasicSerializer(serializers.ModelSerializer):
    class Meta:
        model = Room
        fields = ('id', 'room_code', 'name')
        read_only_fields = ('id', 'room_code', 'name')




class TrackHistorySerializer(serializers.ModelSerializer):
    class Meta:
        model = Track
        fields = ('id', 'title', 'artist', 'cover_url')
        read_only_fields = ('id', 'title', 'artist', 'cover_url')


class GameHistoryEntrySerializer(serializers.ModelSerializer):
    room = RoomBasicSerializer(read_only=True)
    date = serializers.DateField(source='daily_song.date', read_only=True)
    track = serializers.SerializerMethodField()

    class Meta:
        model = DailyGameSession
        fields = (
            'id', 'date', 'room', 'track', 'correct_guess',
            'points_earned', 'current_snippet', 'guesses_made',
            'completed_at'
        )
        read_only_fields = (
            'id', 'date', 'room', 'track', 'correct_guess',
            'points_earned', 'current_snippet', 'guesses_made',
            'completed_at'
        )

    def get_track(self, obj):
        if not obj.daily_song or not obj.daily_song.track:
            return None
        return TrackHistorySerializer(obj.daily_song.track).data
