import uuid
import random
import string
from django.core.exceptions import ValidationError
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
    cover_url = models.URLField(max_length=500, blank=True, null=True, help_text="Album cover image URL")
    deezer_id = models.BigIntegerField(null=True, blank=True, help_text="Deezer track ID for fetching fresh preview URLs")
    release_year = models.PositiveSmallIntegerField(null=True, blank=True, help_text="Year the track was released")
    genre = models.CharField(max_length=100, blank=True, null=True, help_text="Music genre (e.g. Pop, Rock, Hip-Hop)")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'tracks'
        indexes = [
            models.Index(fields=['title']),
            models.Index(fields=['artist']),
        ]

    def __str__(self):
        return f"{self.title} - {self.artist}"

    def get_fresh_preview_url(self, prefer_cached: bool = True, force_refresh: bool = False):
        """
        Fetch a fresh preview URL from Deezer API.
        Returns the cached preview URL when available to avoid extra requests.
        """
        if prefer_cached and self.preview_url and not force_refresh:
            return self.preview_url
        if not self.deezer_id:
            return self.preview_url

        from .services import DeezerService
        deezer = DeezerService()
        track_data = deezer.get_track(self.deezer_id)

        if track_data and track_data.get('preview'):
            preview_url = track_data['preview']
            album = track_data.get('album', {})
            cover_url = (
                album.get('cover_xl') or
                album.get('cover_big') or
                album.get('cover_medium') or
                album.get('cover_small') or
                album.get('cover')
            )
            update_fields = []
            if preview_url and preview_url != self.preview_url:
                self.preview_url = preview_url
                update_fields.append('preview_url')
            if cover_url and not self.cover_url:
                self.cover_url = cover_url
                update_fields.append('cover_url')
            if update_fields:
                self.save(update_fields=update_fields)
            return preview_url

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
    price_coins = models.PositiveIntegerField(default=1000, help_text="Price in coins")
    is_free = models.BooleanField(default=False, help_text="Free packs available to all users")
    is_featured = models.BooleanField(default=False, help_text="Featured packs shown prominently")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'song_packs'
        ordering = ['-is_featured', 'name']

    def __str__(self):
        return self.name

    @property
    def track_count(self):
        return self.pack_tracks.count()


class UserPack(models.Model):
    """
    Tracks which packs each user has purchased/unlocked.
    """
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='owned_packs'
    )
    pack = models.ForeignKey(
        SongPack,
        on_delete=models.CASCADE,
        related_name='owners'
    )
    purchased_at = models.DateTimeField(auto_now_add=True)
    coins_spent = models.PositiveIntegerField(default=0)

    class Meta:
        db_table = 'user_packs'
        unique_together = [['user', 'pack']]
        ordering = ['-purchased_at']

    def __str__(self):
        return f"{self.user.username} owns {self.pack.name}"


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
    vocals_url = models.URLField(max_length=500, blank=True, null=True, help_text="Stem URL for vocals")
    drums_url = models.URLField(max_length=500, blank=True, null=True, help_text="Stem URL for drums")
    bass_url = models.URLField(max_length=500, blank=True, null=True, help_text="Stem URL for bass")
    other_url = models.URLField(max_length=500, blank=True, null=True, help_text="Stem URL for other instruments")

    class Meta:
        db_table = 'pack_tracks'
        unique_together = [['pack', 'track']]
        ordering = ['order_in_pack']
        indexes = [
            models.Index(fields=['pack', 'order_in_pack']),
        ]

    def clean(self):
        if not self.pack_id:
            return
        existing_count = self.pack.pack_tracks.exclude(id=self.id).count()
        if existing_count >= 30:
            raise ValidationError("A pack cannot have more than 30 tracks.")

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
    name = models.CharField(max_length=50, blank=True, null=True, help_text="Custom room name")
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
        if self.name:
            return f"{self.name} ({self.room_code})"
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


class RoomPack(models.Model):
    """
    Tracks which packs have been purchased for a room.
    """
    room = models.ForeignKey(
        Room,
        on_delete=models.CASCADE,
        related_name='room_packs'
    )
    pack = models.ForeignKey(
        SongPack,
        on_delete=models.CASCADE,
        related_name='room_purchases'
    )
    purchased_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='room_pack_purchases'
    )
    purchased_at = models.DateTimeField(auto_now_add=True)
    coins_spent = models.PositiveIntegerField(default=0)

    class Meta:
        db_table = 'room_packs'
        unique_together = [['room', 'pack']]
        ordering = ['-purchased_at']
        indexes = [
            models.Index(fields=['room', 'pack']),
        ]

    def __str__(self):
        return f"{self.room.room_code} owns {self.pack.name}"


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


class PackDailyTrack(models.Model):
    """
    Tracks the daily selected pack track for each room/pack.
    One track per room pack per day.
    """
    room = models.ForeignKey(
        Room,
        on_delete=models.CASCADE,
        related_name='pack_daily_tracks'
    )
    pack = models.ForeignKey(
        SongPack,
        on_delete=models.CASCADE,
        related_name='daily_tracks'
    )
    track = models.ForeignKey(
        Track,
        on_delete=models.CASCADE,
        related_name='pack_daily_tracks'
    )
    date = models.DateField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'pack_daily_tracks'
        unique_together = [['room', 'pack', 'date']]
        ordering = ['-date']
        indexes = [
            models.Index(fields=['room', 'date']),
            models.Index(fields=['pack', 'date']),
        ]

    def __str__(self):
        return f"{self.room.room_code} - {self.pack.name} on {self.date}"


class PackBundleSession(models.Model):
    """
    Tracks a user's progress through today's pack bundle (stem-based guessing).
    One session per user per room per pack per day.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    room = models.ForeignKey(
        Room,
        on_delete=models.CASCADE,
        related_name='pack_bundle_sessions'
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='pack_bundle_sessions'
    )
    pack = models.ForeignKey(
        SongPack,
        on_delete=models.CASCADE,
        related_name='bundle_sessions'
    )
    pack_daily_track = models.ForeignKey(
        PackDailyTrack,
        on_delete=models.CASCADE,
        related_name='bundle_sessions',
        null=True,
        blank=True
    )
    current_stage = models.PositiveSmallIntegerField(default=1)
    points_earned = models.PositiveIntegerField(default=0)
    hints_used = models.JSONField(default=list, blank=True, help_text="List of hint types purchased, e.g. ['genre', 'artist_letter']")
    completed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'pack_bundle_sessions'
        unique_together = [['room', 'user', 'pack', 'pack_daily_track']]
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['room', 'pack']),
            models.Index(fields=['user', 'pack']),
        ]

    def __str__(self):
        return f"{self.user.username} - {self.pack.name} on {self.pack_daily_track.date}"


class PackBundleAttempt(models.Model):
    """
    Tracks each guess attempt for a pack bundle session.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    session = models.ForeignKey(
        PackBundleSession,
        on_delete=models.CASCADE,
        related_name='attempts'
    )
    pack_track = models.ForeignKey(
        PackTrack,
        on_delete=models.CASCADE,
        related_name='bundle_attempts'
    )
    stage = models.PositiveSmallIntegerField()
    guessed_track = models.ForeignKey(
        Track,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='bundle_guesses'
    )
    is_correct = models.BooleanField(default=False)
    points_awarded = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'pack_bundle_attempts'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['session', 'stage']),
            models.Index(fields=['pack_track']),
        ]

    def __str__(self):
        return f"{self.session.user.username} - {self.pack_track} (stage {self.stage})"


class PackBundleStemJob(models.Model):
    """
    Tracks async stem generation per pack track.
    """
    STATUS_QUEUED = 'queued'
    STATUS_RUNNING = 'running'
    STATUS_READY = 'ready'
    STATUS_FAILED = 'failed'
    STATUS_CHOICES = [
        (STATUS_QUEUED, 'Queued'),
        (STATUS_RUNNING, 'Running'),
        (STATUS_READY, 'Ready'),
        (STATUS_FAILED, 'Failed'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    pack_track = models.OneToOneField(
        PackTrack,
        on_delete=models.CASCADE,
        related_name='stem_job'
    )
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_QUEUED)
    error_message = models.TextField(blank=True)
    started_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'pack_bundle_stem_jobs'
        indexes = [
            models.Index(fields=['status', 'created_at']),
        ]

    def __str__(self):
        return f"{self.pack_track} - {self.status}"


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
    hints_used = models.JSONField(default=list, blank=True, help_text="List of hint types purchased, e.g. ['genre', 'artist_letter']")
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


class PackBundleMessage(models.Model):
    """
    Message board for pack bundle discussion (scoped per room/pack/day).
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    room = models.ForeignKey(
        Room,
        on_delete=models.CASCADE,
        related_name='pack_bundle_messages'
    )
    pack = models.ForeignKey(
        SongPack,
        on_delete=models.CASCADE,
        related_name='bundle_messages'
    )
    pack_daily_track = models.ForeignKey(
        PackDailyTrack,
        on_delete=models.CASCADE,
        related_name='bundle_messages'
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='pack_bundle_messages'
    )
    message = models.TextField(max_length=500)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'pack_bundle_messages'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['pack_daily_track', 'created_at']),
            models.Index(fields=['room', 'pack']),
        ]

    def __str__(self):
        return f"{self.user.username} in {self.room.room_code} ({self.pack.name}): {self.message[:50]}"
