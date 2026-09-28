import uuid
from django.db import models
from django.conf import settings


class Track(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    title = models.CharField(max_length=255)
    artist = models.CharField(max_length=255)
    # Whether Deezer has ever handed us audio for this release.
    #
    # Not the URL itself: Deezer signs previews with a fifteen-minute expiry,
    # so a stored URL is dead audio almost every time it is read. Keeping one
    # as an "outage fallback" was tempting and wrong — any row older than a
    # quarter of an hour has an expired URL, so the fallback would essentially
    # never fire, while costing 266 bytes on every row in the table.
    #
    # The real URL is resolved at play time; see game/services/previews.py.
    has_preview = models.BooleanField(default=False)
    cover_url = models.URLField(max_length=500, blank=True, null=True)
    deezer_id = models.BigIntegerField(null=True, blank=True, db_index=True)
    deezer_artist_id = models.BigIntegerField(null=True, blank=True, db_index=True)
    release_year = models.PositiveSmallIntegerField(null=True, blank=True)
    genre = models.CharField(max_length=100, blank=True, null=True)
    rank = models.PositiveIntegerField(
        default=0,
        help_text="Deezer popularity score. Gates the undirected pick, never an answer.",
    )
    # Release-agnostic identity. Deezer ships one row per *release*, so the
    # album cut, the single and the live version of one song are different
    # tracks; these two columns are what make them the same answer. Maintained
    # in save(), never set by hand.
    contributors = models.JSONField(default=list, blank=True)
    search_title = models.TextField(blank=True, default='')
    search_artist = models.TextField(blank=True, default='')
    norm_title = models.CharField(max_length=1024, blank=True, default='', db_index=True)
    norm_artist = models.CharField(max_length=1024, blank=True, default='', db_index=True)
    last_seen_at = models.DateTimeField(null=True, blank=True)
    # True when the track came from a Deezer chart or editorial playlist rather
    # than open search. That provenance *is* a popularity signal — a better one
    # than follower counts, which are heavily skewed towards Deezer's European
    # audience — so curated tracks bypass the popularity floors. Without this,
    # a 50 000-fan floor leaves "Top J-Pop" with seven playable songs out of
    # sixty-one, and Bollywood with fifteen out of a hundred.
    is_curated = models.BooleanField(default=False)
    # A remaster, live cut, remix or radio edit. Kept in the catalogue on
    # purpose — a live take is a perfectly correct *answer* — but never chosen
    # when the game is the one picking.
    #
    # This has to be a stored column rather than a check at pick time, because
    # the import-time check is skipped for directed picks: an artist session on
    # The Weeknd legitimately pulls "Blinding Lights (Live)" into the table,
    # and without this it would then be eligible for a category round. Album
    # walks make that worse, since their tracks often carry rank 0, which
    # passes the popularity floor by design.
    is_variant = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'tracks'
        indexes = [
            # Search is served by trigram GIN indexes, created in migration
            # 0014 rather than declared here: development runs on SQLite, which
            # has no pg_trgm. The B-tree indexes that used to sit on `title`
            # and `artist` were dropped there — they could not answer the
            # leading-wildcard LIKE that is the only way those columns are
            # queried.
            models.Index(fields=['norm_title', 'norm_artist']),
        ]
        constraints = [
            # The catalogue is now a write-through cache of Deezer, filled from
            # several paths at once (search, artist tops, chart refresh). Without
            # this, the same track imported by two paths lands twice and the
            # dedup in search results has to clean up after every import.
            models.UniqueConstraint(
                fields=['deezer_id'],
                condition=models.Q(deezer_id__isnull=False),
                name='uniq_track_deezer_id',
            ),
        ]

    def __str__(self):
        return f"{self.title} - {self.artist}"

    def save(self, *args, **kwargs):
        from .services.matching import is_variant_title, normalize_artist, normalize_title

        from .services.matching import normalize_query
        self.search_title = normalize_query(self.title)
        self.search_artist = normalize_query(self.artist)
        self.norm_title = normalize_title(self.title)
        self.norm_artist = normalize_artist(self.artist)
        self.is_variant = is_variant_title(self.title)
        update_fields = kwargs.get('update_fields')
        if update_fields is not None:
            update_fields = set(update_fields)
            if 'title' in update_fields:
                update_fields.update(['norm_title', 'search_title'])
            if 'artist' in update_fields:
                update_fields.update(['norm_artist', 'search_artist'])
            if 'title' in update_fields:
                update_fields.add('is_variant')
            kwargs['update_fields'] = tuple(update_fields)
        super().save(*args, **kwargs)

class Artist(models.Model):
    """
    A Deezer artist entity, cached locally.

    Artists are addressed by Deezer ID rather than by name from here on. Name
    lookup is ambiguous in a way that matters: `search/artist?q=weeknd` returns
    "Weeknd" (2k fans) *above* "The Weeknd" (14.6M), and "The Retro Weeknd", a
    covers act whose tracks are literally titled "Blinding Lights (Original
    Mix)". Pinning the ID is what stops a player who picked one artist from
    being played another.
    """
    deezer_id = models.BigIntegerField(primary_key=True)
    name = models.CharField(max_length=255)
    # Normalization can expand a valid 255-character credit (e.g. & -> and).
    norm_name = models.CharField(max_length=1024, blank=True, default='', db_index=True)
    picture_url = models.URLField(max_length=500, blank=True, null=True)
    nb_fan = models.PositiveIntegerField(default=0, db_index=True)
    # Set for karaoke/tribute/cover acts. Keeps them out of undirected picks;
    # a player who deliberately selects one can still play it.
    is_junk = models.BooleanField(default=False)
    # Manual override for anything that has to disappear entirely.
    is_blocked = models.BooleanField(default=False)
    top_refreshed_at = models.DateTimeField(null=True, blank=True)
    # Unlike the background top-tracks crawl, directed play also walks albums.
    directed_refreshed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'artists'
        ordering = ['-nb_fan']

    def __str__(self):
        return f"{self.name} ({self.nb_fan} fans)"

    def save(self, *args, **kwargs):
        from .services.matching import is_junk_artist, normalize_artist

        self.norm_name = normalize_artist(self.name)
        if is_junk_artist(self.name):
            self.is_junk = True
        super().save(*args, **kwargs)
        if self.is_junk or self.is_blocked:
            # Only the flagged ones, so a crawl saving thousands of ordinary
            # artists does not evict the list it is about to read back. Imported
            # here rather than at module scope: services.catalog imports this
            # module.
            from .services.catalog import clear_junk_artist_cache

            clear_junk_artist_cache()


class CatalogSetting(models.Model):
    """
    Tunables for the open catalogue, editable from the admin.

    These thresholds decide what the game is willing to *play at you* when you
    have not named an artist. They are settings rather than constants because
    the right value is only knowable from real play: too low and the pool fills
    with covers, too high and whole genres thin out. Changing them must not
    require a deploy.
    """
    singleton_id = models.PositiveSmallIntegerField(primary_key=True, default=1)

    min_artist_fans = models.PositiveIntegerField(
        default=50_000,
        help_text='Undirected picks only play artists with at least this many Deezer fans.',
    )
    min_track_rank = models.PositiveIntegerField(
        default=200_000,
        help_text='Undirected picks only play tracks at or above this Deezer rank.',
    )
    artist_top_ttl_days = models.PositiveSmallIntegerField(
        default=7,
        help_text="How long an artist's cached top-tracks list stays fresh.",
    )
    playlist_ttl_hours = models.PositiveSmallIntegerField(
        default=24,
        help_text='How long a category pool stays fresh before a background refresh.',
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'catalog_settings'
        verbose_name = 'Catalog settings'
        verbose_name_plural = 'Catalog settings'

    def __str__(self):
        return 'Catalog settings'

    def save(self, *args, **kwargs):
        self.singleton_id = 1
        super().save(*args, **kwargs)
        self.__class__.clear_cache()

    _CACHE_KEY = 'catalog_settings_v1'
    _SHARED_TTL = 300
    # Second, process-local tier in front of the shared cache. The thresholds
    # are read once per candidate track, so an import loop asks for them
    # hundreds of times in a row; without this that is hundreds of Redis round
    # trips, and against an unreachable Redis it is hundreds of connect
    # timeouts. The cost is that an admin edit takes up to _LOCAL_TTL seconds
    # to reach a running worker.
    _LOCAL_TTL = 30
    _local = None

    @classmethod
    def clear_cache(cls):
        from .services.cache_utils import cache_delete
        cls._local = None
        cache_delete(cls._CACHE_KEY)

    @classmethod
    def get_solo(cls) -> 'CatalogSetting':
        """The single settings row. Read on every pick, so kept close to hand."""
        import time

        from .services.cache_utils import cache_get, cache_set

        if cls._local is not None:
            expires_at, obj = cls._local
            if time.monotonic() < expires_at:
                return obj

        obj = cache_get(cls._CACHE_KEY)
        if obj is None:
            obj, _ = cls.objects.get_or_create(singleton_id=1)
            cache_set(cls._CACHE_KEY, obj, cls._SHARED_TTL)

        cls._local = (time.monotonic() + cls._LOCAL_TTL, obj)
        return obj


class SearchMiss(models.Model):
    """
    A guess-box query the catalogue could not answer.

    This is the crawler's priority queue, written by the only party that knows
    what is missing: the players. An artist absent from the catalogue is
    invisible — nobody can report it, and it shows up as a one-star review
    saying the app does not have their music. A miss recorded here becomes a
    seed for the next `crawl_artists` run.

    Keyed on the normalised query so `Rosalía` and `rosalia` are one row.
    """
    norm_query = models.CharField(max_length=255, unique=True)
    query = models.CharField(max_length=255)
    hits = models.PositiveIntegerField(default=1)
    crawled_at = models.DateTimeField(
        null=True, blank=True,
        help_text='When the crawler last used this as a seed. Blank means pending.',
    )
    last_seen_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'search_misses'
        ordering = ['-hits']
        indexes = [
            models.Index(fields=['crawled_at', '-hits']),
        ]

    def __str__(self):
        return f'{self.query} ({self.hits})'


class SearchEnrichment(models.Model):
    """
    A query already sent to Deezer, so it is not sent again for a week.

    This lived in the Redis cache and could not survive there. Redis runs at
    its 2GB cap under `allkeys-lru`, evicting whatever is coldest, and a claim
    is by nature never read again once written — so it was always among the
    first to go, gone in hours rather than the week it was set for. Every lost
    claim reopened its query for enrichment, and the same fifty tracks were
    imported again the next time somebody typed it. That is what held track
    ingestion at a floor of ~17k rows an hour that never decayed, against a
    design meant to quieten down as the gaps players hit get filled.

    Deliberately not folded into `SearchMiss`, which looks similar and is not:
    a miss is a query with *no* answer at all and is the crawler's seed queue,
    while a claim is also taken for queries that returned a few rows. Writing
    these there would feed the crawler seeds it should never follow.
    """
    kind = models.CharField(max_length=16, help_text="'tracks' or 'artists'.")
    norm_query = models.CharField(max_length=255)
    enriched_at = models.DateTimeField()
    state = models.CharField(max_length=16, default='legacy', db_index=True)
    query = models.CharField(max_length=255, default='')
    next_attempt_at = models.DateTimeField(null=True, db_index=True)
    lease_until = models.DateTimeField(null=True)
    lease_token = models.UUIDField(null=True)
    attempts = models.PositiveIntegerField(default=0)
    last_error = models.CharField(max_length=64, default='')
    # For a query only Deezer could answer (a typo, a missing space): the
    # tracks it matched that resemble the query. Kept for as long as the claim
    # holds, so the next player who types it sees the same list. See
    # catalog.search_tracks.
    track_ids = models.JSONField(null=True, blank=True)

    class Meta:
        db_table = 'search_enrichments'
        constraints = [
            models.UniqueConstraint(
                fields=['kind', 'norm_query'], name='uniq_search_enrichment',
            ),
        ]

    def __str__(self):
        return f'{self.kind}:{self.norm_query}'


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
    ('latino', 'Latino'),
    ('afrobeats', 'Afrobeats'),
    ('jpop', 'J-pop'),
    ('bollywood', 'Bollywood'),
    ('disco', 'Disco / Funk / Soul'),
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
    # Where this category refills itself from. The pool is no longer a fixed
    # seeded list: refresh_catalog pages these sources and writes the results
    # through to `tracks`, so a session can no longer run the category dry.
    deezer_genre_id = models.IntegerField(
        null=True, blank=True,
        help_text='Deezer genre ID for /chart/{id}/tracks. Blank if playlist-sourced only.',
    )
    deezer_playlist_ids = models.JSONField(
        default=list, blank=True,
        help_text='Deezer editorial playlist IDs, for categories with no genre chart (Rap FR, Bollywood).',
    )
    refreshed_at = models.DateTimeField(null=True, blank=True)
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
    # How well known the song is: the best Deezer rank among all its releases,
    # recorded by refresh_catalog. The all-genre mix plays only the better
    # known part of each category (see services/pools.MIX_TOP_SHARE).
    song_rank = models.PositiveIntegerField(default=0)

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
    # Null for rows saved before the catalogue opened up; those still resolve
    # by name, so existing favourites keep working untouched.
    artist_deezer_id = models.BigIntegerField(null=True, blank=True, db_index=True)
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
    session_uuid = models.UUIDField(null=True, blank=True, db_index=True)
    is_partial = models.BooleanField(default=False)

    class Meta:
        db_table = 'game_scores'
        ordering = ['-played_at']
        indexes = [
            models.Index(fields=['user', '-played_at']),
            models.Index(fields=['genre', '-total_score']),
            models.Index(fields=['-total_score']),
            models.Index(fields=['played_at']),
        ]
        constraints = [
            # A session submits several times (partial checkpoints, then the
            # final score). Without this, concurrent submits both miss on
            # get_or_create and insert, leaving duplicates that make every
            # later update_or_create raise MultipleObjectsReturned.
            models.UniqueConstraint(
                fields=['user', 'session_uuid'],
                condition=models.Q(session_uuid__isnull=False),
                name='uniq_gamescore_user_session',
            ),
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


class SearchOutbox(models.Model):
    """Transactional change log. Consumers always re-read the current source row."""
    kind = models.CharField(max_length=16)
    entity_id = models.CharField(max_length=64)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'search_outbox'


class DeezerBudget(models.Model):
    """Non-evictable coordination shared by every process on this database."""
    id = models.PositiveSmallIntegerField(primary_key=True, default=1)
    calls = models.JSONField(default=list)
