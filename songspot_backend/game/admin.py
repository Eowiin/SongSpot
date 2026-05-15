from django.contrib import admin
from .models import Track, Playlist, PlaylistTrack, GameScore, UserBest, FavouriteArtist


@admin.register(Track)
class TrackAdmin(admin.ModelAdmin):
    list_display = ('title', 'artist', 'genre', 'release_year', 'created_at')
    search_fields = ('title', 'artist')
    list_filter = ('genre', 'created_at')
    readonly_fields = ('id', 'created_at')


class PlaylistTrackInline(admin.TabularInline):
    model = PlaylistTrack
    extra = 0
    autocomplete_fields = ['track']


@admin.register(Playlist)
class PlaylistAdmin(admin.ModelAdmin):
    list_display = ('name', 'category', 'track_count', 'created_at')
    search_fields = ('name', 'description')
    list_filter = ('category', 'created_at')
    readonly_fields = ('id', 'created_at')
    inlines = [PlaylistTrackInline]


@admin.register(PlaylistTrack)
class PlaylistTrackAdmin(admin.ModelAdmin):
    list_display = ('playlist', 'track', 'order_in_playlist')
    list_filter = ('playlist',)
    search_fields = ('playlist__name', 'track__title')
    ordering = ('playlist', 'order_in_playlist')


@admin.register(GameScore)
class GameScoreAdmin(admin.ModelAdmin):
    list_display = ('user', 'genre', 'artist_filter', 'total_score', 'best_streak', 'songs_played', 'played_at')
    list_filter = ('genre', 'played_at')
    search_fields = ('user__username', 'user__email', 'artist_filter')
    readonly_fields = ('id', 'played_at')
    ordering = ('-played_at',)


@admin.register(UserBest)
class UserBestAdmin(admin.ModelAdmin):
    list_display = ('user', 'best_score_overall', 'best_streak_overall', 'total_songs_played', 'total_songs_correct')
    search_fields = ('user__username', 'user__email')
    ordering = ('-best_score_overall',)


@admin.register(FavouriteArtist)
class FavouriteArtistAdmin(admin.ModelAdmin):
    list_display = ('user', 'artist_name', 'created_at')
    search_fields = ('user__username', 'artist_name')
    ordering = ('-created_at',)
