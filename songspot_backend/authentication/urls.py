from django.urls import path
from .views import (
    RegisterView,
    LoginView,
    LogoutView,
    RefreshTokenView,
    UserProfileView,
    PushDeviceRegisterView,
    PushDeviceUnregisterView,
)

app_name = 'authentication'

urlpatterns = [
    path('register/', RegisterView.as_view(), name='register'),
    path('login/', LoginView.as_view(), name='login'),
    path('logout/', LogoutView.as_view(), name='logout'),
    path('token/refresh/', RefreshTokenView.as_view(), name='token_refresh'),
    path('profile/', UserProfileView.as_view(), name='profile'),
    path('push/devices/register/', PushDeviceRegisterView.as_view(), name='push_device_register'),
    path('push/devices/unregister/', PushDeviceUnregisterView.as_view(), name='push_device_unregister'),
]
