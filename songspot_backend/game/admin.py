from django.contrib import admin
from .models import Track, SongPack, PackTrack, GameScore, UserBest, FavouriteArtist


@admin.register(Track)
class TrackAdmin(admin.ModelAdmin):
    list_display = ('title', 'artist', 'genre', 'release_year', 'created_at')
    search_fields = ('title', 'artist')
    list_filter = ('genre', 'created_at')
    readonly_fields = ('id', 'created_at')


class PackTrackInline(admin.TabularInline):
    model = PackTrack
    extra = 1
    autocomplete_fields = ['track']


@admin.register(SongPack)
class SongPackAdmin(admin.ModelAdmin):
    list_display = ('name', 'category', 'track_count', 'created_at')
    search_fields = ('name', 'description')
    list_filter = ('category', 'created_at')
    readonly_fields = ('id', 'created_at')
    inlines = [PackTrackInline]


@admin.register(PackTrack)
class PackTrackAdmin(admin.ModelAdmin):
    list_display = ('pack', 'track', 'order_in_pack')
    list_filter = ('pack',)
    search_fields = ('pack__name', 'track__title')
    ordering = ('pack', 'order_in_pack')


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
