from django.contrib import admin
from .models import (
    Track, SongPack, PackTrack, Room, RoomUser, DailySong,
    DailyGameSession, GuessAttempt, RoomMessage
)


@admin.register(Track)
class TrackAdmin(admin.ModelAdmin):
    list_display = ('title', 'artist', 'created_at')
    search_fields = ('title', 'artist')
    list_filter = ('created_at',)
    readonly_fields = ('id', 'created_at')


class PackTrackInline(admin.TabularInline):
    model = PackTrack
    extra = 1
    autocomplete_fields = ['track']


@admin.register(SongPack)
class SongPackAdmin(admin.ModelAdmin):
    list_display = ('name', 'created_at')
    search_fields = ('name', 'description')
    list_filter = ('created_at',)
    readonly_fields = ('id', 'created_at')
    inlines = [PackTrackInline]


@admin.register(PackTrack)
class PackTrackAdmin(admin.ModelAdmin):
    list_display = ('pack', 'track', 'order_in_pack')
    list_filter = ('pack',)
    search_fields = ('pack__name', 'track__title')
    ordering = ('pack', 'order_in_pack')


class RoomUserInline(admin.TabularInline):
    model = RoomUser
    extra = 0
    readonly_fields = ('joined_at',)


@admin.register(Room)
class RoomAdmin(admin.ModelAdmin):
    list_display = ('room_code', 'host_user', 'created_at')
    search_fields = ('room_code', 'host_user__username', 'host_user__email')
    list_filter = ('created_at',)
    readonly_fields = ('id', 'created_at')
    inlines = [RoomUserInline]


@admin.register(RoomUser)
class RoomUserAdmin(admin.ModelAdmin):
    list_display = ('room', 'user', 'joined_at')
    list_filter = ('joined_at',)
    search_fields = ('room__room_code', 'user__username', 'user__email')
    readonly_fields = ('joined_at',)


@admin.register(DailySong)
class DailySongAdmin(admin.ModelAdmin):
    list_display = ('room', 'track', 'date', 'created_at')
    list_filter = ('date', 'created_at')
    search_fields = ('room__room_code', 'track__title', 'track__artist')
    readonly_fields = ('created_at',)
    ordering = ('-date', 'room')


class GuessAttemptInline(admin.TabularInline):
    model = GuessAttempt
    extra = 0
    readonly_fields = ('snippet_number', 'guessed_title', 'guessed_artist', 'is_correct', 'created_at')
    can_delete = False


@admin.register(DailyGameSession)
class DailyGameSessionAdmin(admin.ModelAdmin):
    list_display = ('user', 'room', 'current_snippet', 'correct_guess', 'points_earned', 'created_at')
    list_filter = ('correct_guess', 'current_snippet', 'created_at')
    search_fields = ('user__username', 'user__email', 'room__room_code')
    readonly_fields = ('id', 'created_at', 'completed_at')
    inlines = [GuessAttemptInline]
    ordering = ('-created_at',)


@admin.register(GuessAttempt)
class GuessAttemptAdmin(admin.ModelAdmin):
    list_display = ('game_session', 'snippet_number', 'guessed_title', 'guessed_artist', 'is_correct', 'created_at')
    list_filter = ('is_correct', 'snippet_number', 'created_at')
    search_fields = ('game_session__user__username', 'guessed_title', 'guessed_artist')
    readonly_fields = ('created_at',)
    ordering = ('-created_at',)


@admin.register(RoomMessage)
class RoomMessageAdmin(admin.ModelAdmin):
    list_display = ('user', 'room', 'message_preview', 'created_at')
    list_filter = ('created_at',)
    search_fields = ('user__username', 'room__room_code', 'message')
    readonly_fields = ('id', 'created_at')
    ordering = ('-created_at',)

    def message_preview(self, obj):
        return obj.message[:50] + '...' if len(obj.message) > 50 else obj.message
    message_preview.short_description = 'Message'
