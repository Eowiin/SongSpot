from django.urls import path
from .views import (
    RegisterView,
    LoginView,
    LogoutView,
    RefreshTokenView,
    UserProfileView,
    PasswordResetRequestView,
    PushDeviceRegisterView,
    PushDeviceUnregisterView,
    NoAdsPassActivateView,
    RewardedAdClaimView,
    RewardedAdStatusView,
    ChangeEmailView,
    ChangePasswordView,
    DataExportView,
    DeleteAccountView,
)
from .iap_views import CoinProductListView, IAPVerifyView

app_name = 'authentication'

urlpatterns = [
    path('register/', RegisterView.as_view(), name='register'),
    path('login/', LoginView.as_view(), name='login'),
    path('password-reset/request/', PasswordResetRequestView.as_view(), name='password_reset_request'),
    path('logout/', LogoutView.as_view(), name='logout'),
    path('token/refresh/', RefreshTokenView.as_view(), name='token_refresh'),
    path('profile/', UserProfileView.as_view(), name='profile'),
    path('push/devices/register/', PushDeviceRegisterView.as_view(), name='push_device_register'),
    path('push/devices/unregister/', PushDeviceUnregisterView.as_view(), name='push_device_unregister'),
    path('no-ads/activate/', NoAdsPassActivateView.as_view(), name='no_ads_activate'),
    path('ads/reward/', RewardedAdClaimView.as_view(), name='ads_reward_claim'),
    path('ads/reward/status/', RewardedAdStatusView.as_view(), name='ads_reward_status'),
    path('change-email/', ChangeEmailView.as_view(), name='change_email'),
    path('change-password/', ChangePasswordView.as_view(), name='change_password'),
    path('data/export/', DataExportView.as_view(), name='data_export'),
    path('account/', DeleteAccountView.as_view(), name='delete_account'),
    path('coin-products/', CoinProductListView.as_view(), name='coin_products'),
    path('iap/verify/', IAPVerifyView.as_view(), name='iap_verify'),
]
