import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  // Base URL for the API
  static String get baseUrl =>
      dotenv.env['API_BASE_URL']?.trim().isNotEmpty == true
          ? dotenv.env['API_BASE_URL']!.trim()
          : 'http://localhost:8000/api';

  // Auth endpoints
  static const String authRegister = '/auth/register/';
  static const String authLogin = '/auth/login/';
  static const String authLogout = '/auth/logout/';
  static const String authRefresh = '/auth/token/refresh/';
  static const String authProfile = '/auth/profile/';
  static const String pushDevicesRegister = '/auth/push/devices/register/';
  static const String pushDevicesUnregister = '/auth/push/devices/unregister/';

  // Game endpoints
  static const String roomsCreate = '/game/rooms/create/';
  static const String roomsJoin = '/game/rooms/join/';
  static String roomsDetail(String roomId) => '/game/rooms/$roomId/';
  static String roomsLeave(String roomId) => '/game/rooms/$roomId/leave/';
  static String roomsRename(String roomId) => '/game/rooms/$roomId/rename/';
  static const String roomsMyRooms = '/game/rooms/my-rooms/';
  static String roomsDailySong(String roomId) => '/game/rooms/$roomId/daily-song/';

  // Game play endpoints
  static String dailyGame(String roomId) => '/game/rooms/$roomId/daily-game/';
  static String dailyGameSkip(String roomId) => '/game/rooms/$roomId/daily-game/skip/';
  static String dailyGameGuess(String roomId) => '/game/rooms/$roomId/daily-game/guess/';
  static String dailyGameLeaderboard(String roomId) => '/game/rooms/$roomId/daily-game/leaderboard/';

  // Chat endpoints
  static String roomMessages(String roomId) => '/game/rooms/$roomId/messages/';

  // Packs and tracks
  static const String packs = '/game/packs/';
  static const String packsMy = '/game/packs/my/';
  static String packDetail(String packId) => '/game/packs/$packId/';
  static String packPurchase(String packId) => '/game/packs/$packId/purchase/';
  static String packBundle(String roomId, String packId) =>
      '/game/rooms/$roomId/packs/$packId/bundle/';
  static String packBundleSkip(String roomId, String packId) =>
      '/game/rooms/$roomId/packs/$packId/bundle/skip/';
  static String packBundleGuess(String roomId, String packId) =>
      '/game/rooms/$roomId/packs/$packId/bundle/guess/';
  static String packBundleLeaderboard(String roomId, String packId) =>
      '/game/rooms/$roomId/packs/$packId/bundle/leaderboard/';
  static String packBundleMessages(String roomId, String packId) =>
      '/game/rooms/$roomId/packs/$packId/bundle/messages/';
  static const String tracks = '/game/tracks/';
  static const String searchTracks = '/game/tracks/search/';
  static String trackRefreshPreview(String trackId) => '/game/tracks/$trackId/refresh-preview/';

  // History endpoints
  static String roomHistory(String roomId) => '/game/rooms/$roomId/history/';
  static String roomHistoryDetail(String roomId, String date) => '/game/rooms/$roomId/history/$date/';

  // IAP / Coin shop endpoints
  static const String coinProducts = '/auth/coin-products/';
  static const String iapVerify = '/auth/iap/verify/';

  // Hint endpoints
  static String dailyGameHint(String roomId) => '/game/rooms/$roomId/daily-game/hint/';
  static String packBundleHint(String roomId, String packId) =>
      '/game/rooms/$roomId/packs/$packId/bundle/hint/';

  // Account management endpoints
  static const String changeEmail = '/auth/change-email/';
  static const String changePassword = '/auth/change-password/';
  static const String dataExport = '/auth/data/export/';
  static const String deleteAccount = '/auth/account/';

  // Request timeout
  static const Duration timeout = Duration(seconds: 30);
}
