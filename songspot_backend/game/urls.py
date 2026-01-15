from django.urls import path
from .views import (
    RoomCreateView,
    RoomJoinView,
    RoomLeaveView,
    RoomDetailView,
    MyRoomsView,
    SongPackListView,
    TrackListView,
    RoomDailySongView,
    DailyGameView,
    SkipSnippetView,
    SubmitGuessView,
    LeaderboardView,
    RoomMessagesView,
    SearchTracksView,
)

app_name = 'game'

urlpatterns = [
    # Room endpoints
    path('rooms/create/', RoomCreateView.as_view(), name='room_create'),
    path('rooms/join/', RoomJoinView.as_view(), name='room_join'),
    path('rooms/<uuid:room_id>/leave/', RoomLeaveView.as_view(), name='room_leave'),
    path('rooms/<uuid:room_id>/', RoomDetailView.as_view(), name='room_detail'),
    path('rooms/<uuid:room_id>/daily-song/', RoomDailySongView.as_view(), name='room_daily_song'),
    path('rooms/my-rooms/', MyRoomsView.as_view(), name='my_rooms'),

    # Game endpoints
    path('rooms/<uuid:room_id>/daily-game/', DailyGameView.as_view(), name='daily_game'),
    path('rooms/<uuid:room_id>/daily-game/skip/', SkipSnippetView.as_view(), name='skip_snippet'),
    path('rooms/<uuid:room_id>/daily-game/guess/', SubmitGuessView.as_view(), name='submit_guess'),
    path('rooms/<uuid:room_id>/daily-game/leaderboard/', LeaderboardView.as_view(), name='leaderboard'),

    # Chat endpoints
    path('rooms/<uuid:room_id>/messages/', RoomMessagesView.as_view(), name='room_messages'),

    # Song pack endpoints
    path('packs/', SongPackListView.as_view(), name='pack_list'),

    # Track endpoints
    path('tracks/', TrackListView.as_view(), name='track_list'),
    path('tracks/search/', SearchTracksView.as_view(), name='search_tracks'),
]
