from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from .models import User, UserDevicePushToken

class UserAdmin(BaseUserAdmin):
    list_display = ('email', 'username', 'is_staff', 'is_active')
    list_filter = ('is_staff', 'is_active')
    search_fields = ('email', 'username')
    ordering = ('email',)
    fieldsets = (
        (None, {'fields': ('email', 'username', 'password')}),
        ('Permissions', {'fields': ('is_staff', 'is_active')}),
    )
    add_fieldsets = (
        (None, {'fields': ('email', 'username', 'password1', 'password2')}),
    )

admin.site.register(User, UserAdmin)


@admin.register(UserDevicePushToken)
class UserDevicePushTokenAdmin(admin.ModelAdmin):
    list_display = (
        'user',
        'platform',
        'is_active',
        'daily_song_enabled',
        'messages_enabled',
        'last_seen_at',
    )
    list_filter = ('platform', 'is_active', 'daily_song_enabled', 'messages_enabled')
    search_fields = ('user__email', 'user__username', 'device_id', 'token')
    readonly_fields = ('created_at', 'updated_at', 'last_seen_at')
