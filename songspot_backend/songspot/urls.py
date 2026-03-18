"""
URL configuration for songspot project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/6.0/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from authentication.views import PasswordResetConfirmPageView
from . import views

urlpatterns = [
    path('', views.landing_page, name='landing_page'),
    path('logo.png', views.site_logo, name='site_logo'),
    path('privacy', views.privacy_page, name='privacy_page'),
    path('support', views.support_page, name='support_page'),
    path('terms', views.terms_page, name='terms_page'),
    path('account', views.account_page, name='account_page'),
    path('account/delete', views.account_delete_page, name='account_delete_page'),
    path('account/export', views.account_export_page, name='account_export_page'),
    path(
        'reset-password/<uidb64>/<token>/',
        PasswordResetConfirmPageView.as_view(),
        name='password_reset_confirm',
    ),
    path('app-ads.txt', views.app_ads_txt, name='app_ads_txt'),
    path('admin/', admin.site.urls),
    path('api/auth/', include('authentication.urls')),
    path('api/game/', include('game.urls')),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
    urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)
