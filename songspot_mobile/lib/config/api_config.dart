import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  static String? _trimmedEnv(String key) {
    final value = dotenv.env[key]?.trim();
    return value != null && value.isNotEmpty ? value : null;
  }

  static Uri _authorityOnlyUri(Uri uri, {String? schemeOverride}) {
    final port = uri.hasPort && uri.port > 0 ? uri.port : null;
    return Uri(
      scheme: schemeOverride ?? uri.scheme,
      host: uri.host,
      port: port,
    );
  }

  // Base URL for the API
  static String get baseUrl =>
      _trimmedEnv('API_BASE_URL') ?? 'http://localhost:8000/api';

  // Base URL for WebSocket connections. Prefer an explicit production config,
  // and fall back to deriving it from the API origin for local development.
  static Uri get wsBaseUri {
    final configured = _trimmedEnv('WS_BASE_URL');
    if (configured != null) {
      return _authorityOnlyUri(Uri.parse(configured));
    }

    final apiUri = Uri.parse(baseUrl);
    final wsScheme = apiUri.scheme == 'https' ? 'wss' : 'ws';
    return _authorityOnlyUri(apiUri, schemeOverride: wsScheme);
  }

  // Mobile websocket clients need an explicit Origin header because the
  // backend uses AllowedHostsOriginValidator during the upgrade handshake.
  static Uri get webSocketOriginUri {
    final serverUrl = _trimmedEnv('SERVER_URL');
    if (serverUrl != null) {
      return _authorityOnlyUri(Uri.parse(serverUrl));
    }

    final wsUri = wsBaseUri;
    final originScheme = wsUri.scheme == 'wss' ? 'https' : 'http';
    return _authorityOnlyUri(wsUri, schemeOverride: originScheme);
  }

  static Map<String, String> get webSocketHeaders => {
    'Origin': webSocketOriginUri.toString(),
  };

  static Uri roomChatWebSocketUri(String roomId, String token) {
    final port = wsBaseUri.hasPort && wsBaseUri.port > 0
        ? wsBaseUri.port
        : null;
    return Uri(
      scheme: wsBaseUri.scheme,
      host: wsBaseUri.host,
      port: port,
      path: '/ws/room/$roomId/chat/',
      queryParameters: {'token': token},
    );
  }

  // Auth endpoints
  static const String authRegister = '/auth/register/';
  static const String authLogin = '/auth/login/';
  static const String authLogout = '/auth/logout/';
  static const String authRefresh = '/auth/token/refresh/';
  static const String authProfile = '/auth/profile/';
  static const String pushDevicesRegister = '/auth/push/devices/register/';
  static const String pushDevicesUnregister = '/auth/push/devices/unregister/';
  static const String noAdsActivate = '/auth/no-ads/activate/';
  static const String adsRewardClaim = '/auth/ads/reward/';
  static const String adsRewardStatus = '/auth/ads/reward/status/';

  // Game endpoints
  static const String roomsCreate = '/game/rooms/create/';
  static const String roomsJoin = '/game/rooms/join/';
  static String roomsDetail(String roomId) => '/game/rooms/$roomId/';
  static String roomsLeave(String roomId) => '/game/rooms/$roomId/leave/';
  static String roomsRename(String roomId) => '/game/rooms/$roomId/rename/';
  static const String roomsMyRooms = '/game/rooms/my-rooms/';
  static String roomsDailySong(String roomId) =>
      '/game/rooms/$roomId/daily-song/';

  // Game play endpoints
  static String dailyGame(String roomId) => '/game/rooms/$roomId/daily-game/';
  static String dailyGameSkip(String roomId) =>
      '/game/rooms/$roomId/daily-game/skip/';
  static String dailyGameGuess(String roomId) =>
      '/game/rooms/$roomId/daily-game/guess/';
  static String dailyGameRetry(String roomId) =>
      '/game/rooms/$roomId/daily-game/retry/';
  static String dailyGameLeaderboard(String roomId) =>
      '/game/rooms/$roomId/daily-game/leaderboard/';

  // Chat endpoints
  static String roomMessages(String roomId) => '/game/rooms/$roomId/messages/';

  // Packs and tracks
  static const String packs = '/game/packs/';
  static const String packsMy = '/game/packs/my/';
  static String packDetail(String packId) => '/game/packs/$packId/';
  static String packPurchase(String packId) => '/game/packs/$packId/purchase/';
  static String packActivate(String roomId, String packId) =>
      '/game/rooms/$roomId/packs/$packId/activate/';
  static String packBundle(String roomId, String packId) =>
      '/game/rooms/$roomId/packs/$packId/bundle/';
  static String packBundleSkip(String roomId, String packId) =>
      '/game/rooms/$roomId/packs/$packId/bundle/skip/';
  static String packBundleGuess(String roomId, String packId) =>
      '/game/rooms/$roomId/packs/$packId/bundle/guess/';
  static String packBundleRetry(String roomId, String packId) =>
      '/game/rooms/$roomId/packs/$packId/bundle/retry/';
  static String packBundleLeaderboard(String roomId, String packId) =>
      '/game/rooms/$roomId/packs/$packId/bundle/leaderboard/';
  static String packBundleMessages(String roomId, String packId) =>
      '/game/rooms/$roomId/packs/$packId/bundle/messages/';
  static const String tracks = '/game/tracks/';
  static const String searchTracks = '/game/tracks/search/';
  static String trackRefreshPreview(String trackId) =>
      '/game/tracks/$trackId/refresh-preview/';

  // History endpoints
  static String roomHistory(String roomId) => '/game/rooms/$roomId/history/';
  static String roomHistoryDetail(String roomId, String date) =>
      '/game/rooms/$roomId/history/$date/';
  static String packBundleHistory(String roomId, String packId) =>
      '/game/rooms/$roomId/packs/$packId/history/';
  static String packBundleHistoryDetail(
    String roomId,
    String packId,
    String date,
  ) => '/game/rooms/$roomId/packs/$packId/history/$date/';

  // IAP / Coin shop endpoints
  static const String coinProducts = '/auth/coin-products/';
  static const String iapVerify = '/auth/iap/verify/';

  // Hint endpoints
  static String dailyGameHint(String roomId) =>
      '/game/rooms/$roomId/daily-game/hint/';
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
