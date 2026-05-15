import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  static String? _trimmedEnv(String key) {
    final value = dotenv.env[key]?.trim();
    return value != null && value.isNotEmpty ? value : null;
  }

  static String get baseUrl =>
      _trimmedEnv('API_BASE_URL') ?? 'http://localhost:8000/api';

  // Auth endpoints
  static const String authRegister = '/auth/register/';
  static const String authLogin = '/auth/login/';
  static const String authPasswordResetRequest = '/auth/password-reset/request/';
  static const String authLogout = '/auth/logout/';
  static const String authRefresh = '/auth/token/refresh/';
  static const String authProfile = '/auth/profile/';
  static const String pushDevicesRegister = '/auth/push/devices/register/';
  static const String pushDevicesUnregister = '/auth/push/devices/unregister/';
  static const String noAdsActivate = '/auth/no-ads/activate/';
  static const String adsRewardClaim = '/auth/ads/reward/';
  static const String adsRewardStatus = '/auth/ads/reward/status/';
  static const String changeEmail = '/auth/change-email/';
  static const String changePassword = '/auth/change-password/';
  static const String dataExport = '/auth/data/export/';
  static const String deleteAccount = '/auth/account/';

  // Game endpoints
  static const String categories = '/game/categories/';
  static const String nextSong = '/game/next-song/';
  static const String artists = '/game/artists/';
  static const String artistsTrending = '/game/artists/trending/';
  static const String artistsFavourites = '/game/artists/favourites/';
  static String artistFavouriteDetail(String artistName) =>
      '/game/artists/favourites/$artistName/';
  static const String searchTracks = '/game/tracks/search/';
  static String trackRefreshPreview(String trackId) =>
      '/game/tracks/$trackId/refresh-preview/';
  static const String submitScore = '/game/score/';
  static const String userStats = '/game/stats/';
  static const String leaderboard = '/game/leaderboard/';
  static const String migrateGuestStats = '/game/migrate-guest-stats/';

  static const Duration timeout = Duration(seconds: 30);
}
