from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from .models import User, UserDevicePushToken, CoinProduct, IAPReceipt

class UserAdmin(BaseUserAdmin):
    list_display = ('email', 'username', 'is_staff', 'is_active')
    list_filter = ('is_staff', 'is_active')
    fieldsets = (
        (None, {'fields': ('email', 'username', 'password')}),
        ('Permissions', {'fields': ('is_staff', 'is_active')}),
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


@admin.register(CoinProduct)
class CoinProductAdmin(admin.ModelAdmin):
    list_display = ('name', 'product_id', 'coins_amount', 'price_display', 'bonus_label', 'is_active', 'sort_order')
    list_filter = ('is_active',)
    list_editable = ('is_active', 'sort_order')
    search_fields = ('name', 'product_id')
    ordering = ('sort_order',)


@admin.register(IAPReceipt)
class IAPReceiptAdmin(admin.ModelAdmin):
    list_display = ('user', 'store', 'coin_product', 'status', 'coins_credited', 'transaction_id', 'created_at')
    list_filter = ('store', 'status')
    search_fields = ('user__email', 'user__username', 'transaction_id')
    readonly_fields = ('created_at', 'verified_at')
    raw_id_fields = ('user', 'coin_product')
