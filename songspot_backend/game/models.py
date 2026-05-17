import uuid
from django.db import models
from django.conf import settings


class Track(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    title = models.CharField(max_length=255)
    artist = models.CharField(max_length=255)
    preview_url = models.URLField(max_length=500)
    cover_url = models.URLField(max_length=500, blank=True, null=True)
    deezer_id = models.BigIntegerField(null=True, blank=True)
    artist_picture_url = models.URLField(max_length=500, blank=True, null=True)
    release_year = models.PositiveSmallIntegerField(null=True, blank=True)
    genre = models.CharField(max_length=100, blank=True, null=True)
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

        return self.preview_url


CATEGORY_CHOICES = [
    ('pop', 'Pop'),
    ('hiphop', 'Hip-Hop / Rap'),
    ('rock', 'Rock'),
    ('electro', 'Électro'),
    ('dance', 'Dance'),
    ('rnb', 'R&B'),
    ('kpop', 'K-pop'),
    ('rap_fr', 'Rap Français'),
    ('variete_fr', 'Variété Française'),
    ('reggaeton', 'Reggaeton / Urbano'),
    ('latin', 'Latin Pop'),
    ('afrobeats', 'Afrobeats'),
    ('jpop', 'J-pop'),
    ('bollywood', 'Bollywood'),
]


class Playlist(models.Model):
    """
    A curated set of tracks (e.g. "Pop", "Rap Français") for infinite play.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=255)
    description = models.TextField(blank=True)
    icon_url = models.URLField(max_length=500, blank=True)
    category = models.CharField(
        max_length=20, choices=CATEGORY_CHOICES, blank=True, null=True,
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'playlists'
        ordering = ['name']

    def __str__(self):
        return self.name

    @property
    def track_count(self):
        return self.playlist_tracks.count()


class PlaylistTrack(models.Model):
    playlist = models.ForeignKey(
        Playlist,
        on_delete=models.CASCADE,
        related_name='playlist_tracks'
    )
    track = models.ForeignKey(
        Track,
        on_delete=models.CASCADE,
        related_name='in_playlists'
    )
    order_in_playlist = models.PositiveIntegerField(default=0)

    class Meta:
        db_table = 'playlist_tracks'
        unique_together = [['playlist', 'track']]
        ordering = ['order_in_playlist']
        indexes = [
            models.Index(fields=['playlist', 'order_in_playlist']),
        ]

    def __str__(self):
        return f"{self.playlist.name} - {self.track.title}"


class FavouriteArtist(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='favourite_artists',
    )
    artist_name = models.CharField(max_length=255)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'favourite_artists'
        unique_together = [['user', 'artist_name']]
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.user.username} ♥ {self.artist_name}"


class GameScore(models.Model):
    """Score submitted at the end of a play session."""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='game_scores'
    )
    genre = models.CharField(
        max_length=20, blank=True, null=True,
        help_text='Genre key (e.g. pop, hiphop). Null = mixed / all genres.'
    )
    artist_filter = models.CharField(
        max_length=255, blank=True,
        help_text='Artist name when session was artist-scoped'
    )
    DIFFICULTY_CHOICES = [('easy', 'Easy'), ('medium', 'Medium'), ('hard', 'Hard')]
    difficulty = models.CharField(max_length=10, choices=DIFFICULTY_CHOICES, default='medium')
    songs_played = models.PositiveIntegerField(default=0)
    songs_correct = models.PositiveIntegerField(default=0)
    best_streak = models.PositiveIntegerField(default=0)
    total_score = models.PositiveIntegerField(default=0)
    played_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'game_scores'
        ordering = ['-played_at']
        indexes = [
            models.Index(fields=['user', '-played_at']),
            models.Index(fields=['genre', '-total_score']),
            models.Index(fields=['-total_score']),
            models.Index(fields=['played_at']),
        ]

    def __str__(self):
        label = self.genre or self.artist_filter or 'Mix'
        return f"{self.user.username} — {label} — {self.total_score}pts"


class UserElo(models.Model):
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='elo',
    )
    elo = models.IntegerField(default=1000)
    wins = models.PositiveIntegerField(default=0)
    losses = models.PositiveIntegerField(default=0)
    draws = models.PositiveIntegerField(default=0)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'user_elos'

    def __str__(self):
        return f"{self.user.username} — ELO {self.elo}"

    def update(self, opponent_elo: int, result: str):
        """result: 'win' | 'loss' | 'draw'"""
        expected = 1 / (1 + 10 ** ((opponent_elo - self.elo) / 400))
        score = {'win': 1.0, 'loss': 0.0, 'draw': 0.5}[result]
        self.elo = round(self.elo + 32 * (score - expected))
        if result == 'win':
            self.wins += 1
        elif result == 'loss':
            self.losses += 1
        else:
            self.draws += 1
        self.save()


DUEL_STATUS_CHOICES = [
    ('waiting', 'Waiting'),
    ('in_progress', 'In Progress'),
    ('completed', 'Completed'),
    ('abandoned', 'Abandoned'),
]


class DuelMatch(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    player1 = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='duels_as_p1',
    )
    player2 = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='duels_as_p2',
    )
    status = models.CharField(max_length=15, choices=DUEL_STATUS_CHOICES, default='waiting')
    playlist = models.ForeignKey(
        Playlist, on_delete=models.SET_NULL, null=True, blank=True, related_name='duels',
    )
    total_rounds = models.PositiveSmallIntegerField(default=5)
    current_round = models.PositiveSmallIntegerField(default=0)
    player1_score = models.PositiveIntegerField(default=0)
    player2_score = models.PositiveIntegerField(default=0)
    winner = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='duel_wins',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'duel_matches'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['player1', '-created_at']),
            models.Index(fields=['player2', '-created_at']),
            models.Index(fields=['status']),
        ]

    def __str__(self):
        return f"{self.player1.username} vs {self.player2.username} [{self.status}]"

    def get_opponent(self, user):
        return self.player2 if self.player1_id == user.id else self.player1

    def is_player(self, user):
        return user.id in (self.player1_id, self.player2_id)


SNIPPET_POINTS = {1: 100, 2: 80, 3: 60, 4: 40, 5: 20}


class DuelRound(models.Model):
    match = models.ForeignKey(DuelMatch, on_delete=models.CASCADE, related_name='rounds')
    round_number = models.PositiveSmallIntegerField()
    track = models.ForeignKey(Track, on_delete=models.CASCADE, related_name='duel_rounds')

    player1_correct = models.BooleanField(null=True, blank=True)
    player1_points = models.PositiveIntegerField(default=0)
    player1_snippets_used = models.PositiveSmallIntegerField(default=0)
    player1_submitted_at = models.DateTimeField(null=True, blank=True)

    player2_correct = models.BooleanField(null=True, blank=True)
    player2_points = models.PositiveIntegerField(default=0)
    player2_snippets_used = models.PositiveSmallIntegerField(default=0)
    player2_submitted_at = models.DateTimeField(null=True, blank=True)

    started_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'duel_rounds'
        unique_together = [['match', 'round_number']]
        ordering = ['round_number']

    def __str__(self):
        return f"Round {self.round_number} of {self.match}"

    @staticmethod
    def points_for_snippets(snippets_used: int) -> int:
        return SNIPPET_POINTS.get(snippets_used, 0)

    @property
    def both_submitted(self):
        return self.player1_submitted_at is not None and self.player2_submitted_at is not None


class MatchmakingQueue(models.Model):
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='matchmaking_entry',
    )
    elo_at_join = models.IntegerField()
    playlist = models.ForeignKey(
        Playlist, on_delete=models.SET_NULL, null=True, blank=True,
    )
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'matchmaking_queue'

    def __str__(self):
        return f"{self.user.username} in queue (ELO {self.elo_at_join})"


class UserBest(models.Model):
    """
    Denormalized personal bests per user, updated whenever a GameScore beats the record.
    """
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='best'
    )
    best_score_overall = models.PositiveIntegerField(default=0)
    best_streak_overall = models.PositiveIntegerField(default=0)
    total_songs_played = models.PositiveIntegerField(default=0)
    total_songs_correct = models.PositiveIntegerField(default=0)
    per_genre = models.JSONField(
        default=dict,
        help_text='{"pop": {"best_score": 0, "best_streak": 0, "songs_played": 0}}'
    )

    class Meta:
        db_table = 'user_bests'

    def __str__(self):
        return f"{self.user.username} — best {self.best_score_overall}"

    def update_from_score(self, score: 'GameScore'):
        changed = False
        if score.total_score > self.best_score_overall:
            self.best_score_overall = score.total_score
            changed = True
        if score.best_streak > self.best_streak_overall:
            self.best_streak_overall = score.best_streak
            changed = True
        self.total_songs_played += score.songs_played
        self.total_songs_correct += score.songs_correct
        if score.genre:
            entry = self.per_genre.get(score.genre, {'best_score': 0, 'best_streak': 0, 'songs_played': 0})
            entry['songs_played'] += score.songs_played
            if score.total_score > entry['best_score']:
                entry['best_score'] = score.total_score
            if score.best_streak > entry['best_streak']:
                entry['best_streak'] = score.best_streak
            self.per_genre[score.genre] = entry
        self.save()
        return changed
