from django.contrib import admin
from .models import (
    Artist, CatalogSetting, Track, Playlist, PlaylistTrack,
    GameScore, UserBest, FavouriteArtist,
)


@admin.register(Track)
class TrackAdmin(admin.ModelAdmin):
    list_display = ('title', 'artist', 'genre', 'rank', 'release_year', 'created_at')
    search_fields = ('title', 'artist', 'norm_title', 'norm_artist')
    list_filter = ('genre', 'created_at')
    # Maintained by Track.save() from title/artist — editing them by hand would
    # silently change which guesses are accepted for this song.
    readonly_fields = ('id', 'created_at', 'norm_title', 'norm_artist', 'last_seen_at')


@admin.register(Artist)
class ArtistAdmin(admin.ModelAdmin):
    list_display = ('name', 'nb_fan', 'is_junk', 'is_blocked', 'top_refreshed_at')
    search_fields = ('name', 'norm_name')
    list_filter = ('is_junk', 'is_blocked')
    readonly_fields = ('norm_name', 'created_at', 'top_refreshed_at')
    ordering = ('-nb_fan',)


@admin.register(CatalogSetting)
class CatalogSettingAdmin(admin.ModelAdmin):
    """
    The quality floor for undirected picks, tunable without a deploy.

    Only affects rounds the *game* chooses — a category or a duel. A player who
    picks an artist by name is never filtered by these, so raising the floor can
    never hide someone's favourite niche act from them.
    """
    list_display = (
        'min_artist_fans', 'min_track_rank',
        'artist_top_ttl_days', 'playlist_ttl_hours', 'updated_at',
    )
    readonly_fields = ('updated_at',)

    def has_add_permission(self, request):
        # Singleton: the row is created on first read by CatalogSetting.get_solo.
        return not CatalogSetting.objects.exists()

    def has_delete_permission(self, request, obj=None):
        return False


class PlaylistTrackInline(admin.TabularInline):
    model = PlaylistTrack
    extra = 0
    autocomplete_fields = ['track']


@admin.register(Playlist)
class PlaylistAdmin(admin.ModelAdmin):
    list_display = ('name', 'category', 'track_count', 'refreshed_at', 'created_at')
    search_fields = ('name', 'description')
    list_filter = ('category', 'created_at')
    readonly_fields = ('id', 'created_at', 'refreshed_at')
    inlines = [PlaylistTrackInline]


@admin.register(PlaylistTrack)
class PlaylistTrackAdmin(admin.ModelAdmin):
    list_display = ('playlist', 'track', 'order_in_playlist')
    list_filter = ('playlist',)
    search_fields = ('playlist__name', 'track__title')
    ordering = ('playlist', 'order_in_playlist')


@admin.register(GameScore)
class GameScoreAdmin(admin.ModelAdmin):
    list_display = ('user', 'genre', 'artist_filter', 'total_score', 'best_streak', 'songs_played', 'is_partial', 'session_uuid', 'played_at')
    list_filter = ('genre', 'is_partial', 'played_at')
    search_fields = ('user__username', 'user__email', 'artist_filter')
    readonly_fields = ('id', 'played_at', 'session_uuid')
    ordering = ('-played_at',)


@admin.register(UserBest)
class UserBestAdmin(admin.ModelAdmin):
    list_display = ('user', 'best_score_overall', 'best_streak_overall', 'total_songs_played', 'total_songs_correct')
    search_fields = ('user__username', 'user__email')
    ordering = ('-best_score_overall',)


@admin.register(FavouriteArtist)
class FavouriteArtistAdmin(admin.ModelAdmin):
    list_display = ('user', 'artist_name', 'artist_deezer_id', 'created_at')
    search_fields = ('user__username', 'artist_name')
    ordering = ('-created_at',)
