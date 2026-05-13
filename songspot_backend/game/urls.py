from django.urls import path
from .views import (
    CategoryListView,
    NextSongView,
    ArtistListView,
    ArtistTrendingView,
    FavouriteArtistView,
    FavouriteArtistDetailView,
    SearchTracksView,
    TrackRefreshPreviewView,
    SubmitScoreView,
    UserStatsView,
    LeaderboardView,
)

app_name = 'game'

urlpatterns = [
    path('categories/', CategoryListView.as_view(), name='categories'),
    path('next-song/', NextSongView.as_view(), name='next_song'),
    path('artists/', ArtistListView.as_view(), name='artists'),
    path('artists/trending/', ArtistTrendingView.as_view(), name='artists_trending'),
    path('artists/favourites/', FavouriteArtistView.as_view(), name='favourite_artists'),
    path('artists/favourites/<str:artist_name>/', FavouriteArtistDetailView.as_view(), name='favourite_artist_detail'),
    path('tracks/search/', SearchTracksView.as_view(), name='search_tracks'),
    path('tracks/<uuid:track_id>/refresh-preview/', TrackRefreshPreviewView.as_view(), name='track_refresh_preview'),
    path('score/', SubmitScoreView.as_view(), name='submit_score'),
    path('stats/', UserStatsView.as_view(), name='user_stats'),
    path('leaderboard/', LeaderboardView.as_view(), name='leaderboard'),
]
