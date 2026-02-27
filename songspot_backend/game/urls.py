from django.urls import path
from .views import (
    RoomCreateView,
    RoomJoinView,
    RoomLeaveView,
    RoomDetailView,
    RoomRenameView,
    MyRoomsView,
    SongPackListView,
    SongPackDetailView,
    SongPackPurchaseView,
    MyPacksView,
    PackBundleSessionView,
    PackBundleSkipView,
    PackBundleGuessView,
    PackBundleLeaderboardView,
    PackBundleMessagesView,
    DailyGameHintView,
    PackBundleHintView,
    TrackListView,
    TrackRefreshPreviewView,
    RoomDailySongView,
    DailyGameView,
    SkipSnippetView,
    SubmitGuessView,
    DailyGameRetryView,
    LeaderboardView,
    RoomMessagesView,
    SearchTracksView,
    UserGameHistoryView,
    RoomHistoryListView,
    RoomHistoryDetailView,
    PackBundleHistoryListView,
    PackBundleHistoryDetailView,
)

app_name = 'game'

urlpatterns = [
    # Room endpoints
    path('rooms/create/', RoomCreateView.as_view(), name='room_create'),
    path('rooms/join/', RoomJoinView.as_view(), name='room_join'),
    path('rooms/<uuid:room_id>/leave/', RoomLeaveView.as_view(), name='room_leave'),
    path('rooms/<uuid:room_id>/', RoomDetailView.as_view(), name='room_detail'),
    path('rooms/<uuid:room_id>/rename/', RoomRenameView.as_view(), name='room_rename'),
    path('rooms/<uuid:room_id>/daily-song/', RoomDailySongView.as_view(), name='room_daily_song'),
    path('rooms/my-rooms/', MyRoomsView.as_view(), name='my_rooms'),

    # Game endpoints
    path('rooms/<uuid:room_id>/daily-game/', DailyGameView.as_view(), name='daily_game'),
    path('rooms/<uuid:room_id>/daily-game/skip/', SkipSnippetView.as_view(), name='skip_snippet'),
    path('rooms/<uuid:room_id>/daily-game/guess/', SubmitGuessView.as_view(), name='submit_guess'),
    path('rooms/<uuid:room_id>/daily-game/retry/', DailyGameRetryView.as_view(), name='daily_game_retry'),
    path('rooms/<uuid:room_id>/daily-game/leaderboard/', LeaderboardView.as_view(), name='leaderboard'),
    path('rooms/<uuid:room_id>/daily-game/hint/', DailyGameHintView.as_view(), name='daily_game_hint'),

    # Chat endpoints
    path('rooms/<uuid:room_id>/messages/', RoomMessagesView.as_view(), name='room_messages'),

    # Song pack endpoints
    path('packs/', SongPackListView.as_view(), name='pack_list'),
    path('packs/my/', MyPacksView.as_view(), name='my_packs'),
    path('packs/<uuid:pack_id>/', SongPackDetailView.as_view(), name='pack_detail'),
    path('packs/<uuid:pack_id>/purchase/', SongPackPurchaseView.as_view(), name='pack_purchase'),
    path('rooms/<uuid:room_id>/packs/<uuid:pack_id>/bundle/', PackBundleSessionView.as_view(), name='pack_bundle'),
    path('rooms/<uuid:room_id>/packs/<uuid:pack_id>/bundle/skip/', PackBundleSkipView.as_view(), name='pack_bundle_skip'),
    path('rooms/<uuid:room_id>/packs/<uuid:pack_id>/bundle/guess/', PackBundleGuessView.as_view(), name='pack_bundle_guess'),
    path('rooms/<uuid:room_id>/packs/<uuid:pack_id>/bundle/leaderboard/', PackBundleLeaderboardView.as_view(), name='pack_bundle_leaderboard'),
    path('rooms/<uuid:room_id>/packs/<uuid:pack_id>/bundle/messages/', PackBundleMessagesView.as_view(), name='pack_bundle_messages'),
    path('rooms/<uuid:room_id>/packs/<uuid:pack_id>/bundle/hint/', PackBundleHintView.as_view(), name='pack_bundle_hint'),

    # Track endpoints
    path('tracks/', TrackListView.as_view(), name='track_list'),
    path('tracks/<uuid:track_id>/refresh-preview/', TrackRefreshPreviewView.as_view(), name='track_refresh_preview'),
    path('tracks/search/', SearchTracksView.as_view(), name='search_tracks'),

    # User stats/history
    path('history/', UserGameHistoryView.as_view(), name='game_history'),

    # Room-specific history
    path('rooms/<uuid:room_id>/history/', RoomHistoryListView.as_view(), name='room_history_list'),
    path('rooms/<uuid:room_id>/history/<str:date>/', RoomHistoryDetailView.as_view(), name='room_history_detail'),

    # Pack bundle history
    path('rooms/<uuid:room_id>/packs/<uuid:pack_id>/history/', PackBundleHistoryListView.as_view(), name='pack_bundle_history_list'),
    path('rooms/<uuid:room_id>/packs/<uuid:pack_id>/history/<str:date>/', PackBundleHistoryDetailView.as_view(), name='pack_bundle_history_detail'),
]
