import uuid
import random
import string
from django.db import models
from django.conf import settings


class Track(models.Model):
    """
    Music tracks from Deezer API.
    Stores track information including preview URL for the blind test game.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    title = models.CharField(max_length=255)
    artist = models.CharField(max_length=255)
    preview_url = models.URLField(max_length=500)
    deezer_id = models.BigIntegerField(null=True, blank=True, help_text="Deezer track ID for fetching fresh preview URLs")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'tracks'
        indexes = [
            models.Index(fields=['title']),
            models.Index(fields=['artist']),
        ]

    def __str__(self):
        return f"{self.title} - {self.artist}"

    def get_fresh_preview_url(self):
        """
        Fetch a fresh preview URL from Deezer API.
        Returns the current preview_url if deezer_id is not available.
        """
        if not self.deezer_id:
            return self.preview_url

        from .services import DeezerService
        deezer = DeezerService()
        track_data = deezer.get_track(self.deezer_id)

        if track_data and track_data.get('preview'):
            return track_data['preview']

        # Fallback to stored URL if fetch fails
        return self.preview_url


class SongPack(models.Model):
    """
    Purchasable song packs that users can buy.
    Contains a collection of tracks that can be used in rooms.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=255)
    description = models.TextField(blank=True)
    icon_url = models.URLField(max_length=500, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'song_packs'

    def __str__(self):
        return self.name


class PackTrack(models.Model):
    """
    Junction table linking song packs to tracks.
    Maintains the order of tracks within a pack.
    """
    pack = models.ForeignKey(
        SongPack,
        on_delete=models.CASCADE,
        related_name='pack_tracks'
    )
    track = models.ForeignKey(
        Track,
        on_delete=models.CASCADE,
        related_name='in_packs'
    )
    order_in_pack = models.PositiveIntegerField(default=0)

    class Meta:
        db_table = 'pack_tracks'
        unique_together = [['pack', 'track']]
        ordering = ['order_in_pack']
        indexes = [
            models.Index(fields=['pack', 'order_in_pack']),
        ]

    def __str__(self):
        return f"{self.pack.name} - {self.track.title} (#{self.order_in_pack})"


def generate_room_code():
    """Generate a unique 6-character room code."""
    while True:
        code = ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))
        if not Room.objects.filter(room_code=code).exists():
            return code


class Room(models.Model):
    """
    Permanent game rooms where users play together.
    Each room has a unique auto-generated code and a host user.
    Rooms are never deleted, even when empty.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    room_code = models.CharField(max_length=10, unique=True, db_index=True, default=generate_room_code)
    host_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='hosted_rooms'
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'rooms'
        ordering = ['-created_at']

    def __str__(self):
        return f"Room {self.room_code} (Host: {self.host_user.username})"


class RoomUser(models.Model):
    """
    Junction table for users in rooms.
    Tracks when users join rooms.
    """
    room = models.ForeignKey(
        Room,
        on_delete=models.CASCADE,
        related_name='room_users'
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='joined_rooms'
    )
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'room_users'
        unique_together = [['room', 'user']]
        ordering = ['joined_at']

    def __str__(self):
        return f"{self.user.username} in {self.room.room_code}"


class DailySong(models.Model):
    """
    Tracks which song is selected for each room each day.
    One song per room per day.
    """
    room = models.ForeignKey(
        Room,
        on_delete=models.CASCADE,
        related_name='daily_songs'
    )
    track = models.ForeignKey(
        Track,
        on_delete=models.CASCADE,
        related_name='daily_selections'
    )
    date = models.DateField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'daily_songs'
        unique_together = [['room', 'date']]
        ordering = ['-date']
        indexes = [
            models.Index(fields=['room', 'date']),
            models.Index(fields=['date']),
        ]

    def __str__(self):
        return f"{self.room.room_code} - {self.track.title} on {self.date}"


class DailyGameSession(models.Model):
    """
    Tracks user's progress on today's song in a room.
    Users progressively reveal song snippets (0.1s, 0.5s, 2s, 4s, 8s, 15s).
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    room = models.ForeignKey(
        Room,
        on_delete=models.CASCADE,
        related_name='game_sessions'
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='game_sessions'
    )
    daily_song = models.ForeignKey(
        DailySong,
        on_delete=models.CASCADE,
        related_name='game_sessions'
    )
    current_snippet = models.PositiveSmallIntegerField(default=1)
    guesses_made = models.PositiveSmallIntegerField(default=0)
    correct_guess = models.BooleanField(default=False)
    points_earned = models.PositiveSmallIntegerField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'daily_game_sessions'
        unique_together = [['room', 'user', 'daily_song']]
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['room', 'daily_song']),
            models.Index(fields=['user', 'daily_song']),
        ]

    def __str__(self):
        return f"{self.user.username} in {self.room.room_code} - Snippet {self.current_snippet}"


class GuessAttempt(models.Model):
    """
    Individual guess attempts made by users during the game.
    Tracks what they guessed and whether it was correct.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    game_session = models.ForeignKey(
        DailyGameSession,
        on_delete=models.CASCADE,
        related_name='guess_attempts'
    )
    snippet_number = models.PositiveSmallIntegerField()
    guessed_title = models.CharField(max_length=255)
    guessed_artist = models.CharField(max_length=255)
    is_correct = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'guess_attempts'
        ordering = ['created_at']
        indexes = [
            models.Index(fields=['game_session', 'created_at']),
        ]

    def __str__(self):
        status = "✓" if self.is_correct else "✗"
        return f"{status} {self.guessed_title} - {self.guessed_artist} (Snippet {self.snippet_number})"


class RoomMessage(models.Model):
    """
    Simple message board for room discussion.
    Users can post messages visible to all room members.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    room = models.ForeignKey(
        Room,
        on_delete=models.CASCADE,
        related_name='messages'
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='messages'
    )
    message = models.TextField(max_length=500)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'room_messages'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['room', '-created_at']),
        ]

    def __str__(self):
        return f"{self.user.username} in {self.room.room_code}: {self.message[:50]}"
