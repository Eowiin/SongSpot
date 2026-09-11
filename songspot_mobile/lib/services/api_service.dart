import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../l10n/app_localizations.dart';
import 'storage_service.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? errors;
  final String? rawMessage;
  final String? errorCode;
  final Map<String, dynamic>? errorParams;

  ApiException(
    this.message, {
    this.statusCode,
    this.errors,
    this.rawMessage,
    this.errorCode,
    this.errorParams,
  });

  @override
  String toString() => message;
}

class ApiService {
  ApiService._();
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;

  final StorageService _storageService = StorageService();

  /// The token refresh in progress, shared by every request that gets a 401
  /// while it runs.
  ///
  /// Refresh tokens rotate and the old one is blacklisted, so only one refresh
  /// per token can succeed. A second caller used to get an immediate `false`
  /// and throw "Session expired", even though the refresh running alongside
  /// it went on to succeed. Any two requests in flight when the access token
  /// expired (every hour) could fail one of them. Seen with the solo panel
  /// and the style screen loading the categories at the same moment.
  Future<bool>? _refreshInFlight;
  static const String _settingsLocaleKey = 'settings_locale';
  static const String _settingsLocaleManualKey = 'settings_locale_manual';

  Future<Map<String, String>> _getHeaders({bool includeAuth = false}) async {
    final headers = {'Content-Type': 'application/json'};
    if (includeAuth) {
      final token = await _storageService.getAccessToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  String _extractFirstErrorMessage(Map<String, dynamic> body) {
    for (final key in ['error', 'message', 'detail']) {
      final value = body[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is List && value.isNotEmpty && value.first is String) {
        final first = (value.first as String).trim();
        if (first.isNotEmpty) return first;
      }
    }
    for (final entry in body.entries) {
      final value = entry.value;
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is List && value.isNotEmpty && value.first is String) {
        final first = (value.first as String).trim();
        if (first.isNotEmpty) return first;
      }
    }
    return '';
  }

  Future<AppLocalizations> _resolveLocalizations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLanguageCode = prefs.getString(_settingsLocaleKey);
      final localeManuallySelected = prefs.getBool(_settingsLocaleManualKey) ?? false;
      final platformLanguageCode =
          WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      final languageCode = localeManuallySelected && savedLanguageCode != null
          ? savedLanguageCode
          : platformLanguageCode;
      final supported = AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();
      final safeCode = supported.contains(languageCode) ? languageCode : 'en';
      return lookupAppLocalizations(Locale(safeCode));
    } catch (_) {
      return lookupAppLocalizations(const Locale('en'));
    }
  }

  String? _localizeBackendCode(AppLocalizations l10n, String code) {
    switch (code) {
      case 'INVALID_CREDENTIALS':
        return l10n.backendInvalidCredentials;
      case 'INVALID_PASSWORD':
        return l10n.backendInvalidPassword;
      case 'INVALID_CURRENT_PASSWORD':
        return l10n.backendInvalidCurrentPassword;
      case 'INVALID_TOKEN':
        return l10n.backendInvalidToken;
      case 'INVALID_OR_EXPIRED_REFRESH_TOKEN':
        return l10n.backendInvalidOrExpiredRefreshToken;
      case 'REFRESH_TOKEN_REQUIRED':
        return l10n.backendRefreshTokenRequired;
      case 'PASSWORD_RESET_UNAVAILABLE':
        return l10n.backendPasswordResetUnavailable;
      case 'MISSING_REQUIRED_FIELDS':
        return l10n.backendMissingRequiredFields;
      // The round's audio could not be resolved. Deezer signs preview URLs for
      // fifteen minutes, so the server fetches one per round rather than
      // storing it; when it cannot reach Deezer it answers 503 instead of
      // serving a round that would play silence. Distinct from the 404 that
      // ends a session — this one is transient, and the error screen's Retry
      // button is the right thing to do.
      case 'AUDIO_UNAVAILABLE':
        return l10n.backendAudioUnavailable;
      default:
        return null;
    }
  }

  Future<dynamic> _handleResponse(http.Response response) async {
    final statusCode = response.statusCode;
    if (statusCode >= 200 && statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }

    String message = 'Request failed with status: $statusCode';
    Map<String, dynamic>? errors;
    String? rawMessage;
    String? errorCode;
    Map<String, dynamic>? errorParams;

    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        final code = body['error_code'];
        if (code is String && code.trim().isNotEmpty) errorCode = code.trim();
        final params = body['params'];
        if (params is Map) errorParams = Map<String, dynamic>.from(params);
        final extracted = _extractFirstErrorMessage(body);
        if (extracted.isNotEmpty) {
          rawMessage = extracted;
          message = extracted;
        }
        errors = body;
      }
    } catch (_) {}

    if (errorCode != null) {
      try {
        final l10n = await _resolveLocalizations();
        final localized = _localizeBackendCode(l10n, errorCode);
        if (localized != null) message = localized;
      } catch (_) {}
    }

    throw ApiException(
      message,
      statusCode: statusCode,
      errors: errors,
      rawMessage: rawMessage,
      errorCode: errorCode,
      errorParams: errorParams,
    );
  }

  Future<bool> _refreshAccessToken() =>
      _refreshInFlight ??= _refresh().whenComplete(() => _refreshInFlight = null);

  Future<bool> _refresh() async {
    try {
      final refreshToken = await _storageService.getRefreshToken();
      if (refreshToken == null) return false;
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.authRefresh}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refreshToken}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _storageService.saveTokens(
          data['access'] as String,
          data['refresh'] as String,
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<dynamic> get(
    String endpoint, {
    bool includeAuth = false,
    Map<String, String>? queryParameters,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint')
        .replace(queryParameters: queryParameters);
    final headers = await _getHeaders(includeAuth: includeAuth);
    try {
      var response = await http.get(uri, headers: headers).timeout(ApiConfig.timeout);
      if (response.statusCode == 401 && includeAuth) {
        final refreshed = await _refreshAccessToken();
        if (refreshed) {
          final newHeaders = await _getHeaders(includeAuth: includeAuth);
          response = await http.get(uri, headers: newHeaders).timeout(ApiConfig.timeout);
        } else {
          throw ApiException('Session expired. Please login again.', statusCode: 401);
        }
      }
      return await _handleResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      final l10n = await _resolveLocalizations();
      throw ApiException('${l10n.backendNetworkError}: $e');
    }
  }

  Future<dynamic> post(
    String endpoint, {
    Map<String, dynamic>? body,
    bool includeAuth = false,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint');
    final headers = await _getHeaders(includeAuth: includeAuth);
    try {
      var response = await http
          .post(uri, headers: headers, body: body != null ? jsonEncode(body) : null)
          .timeout(ApiConfig.timeout);
      if (response.statusCode == 401 && includeAuth) {
        final refreshed = await _refreshAccessToken();
        if (refreshed) {
          final newHeaders = await _getHeaders(includeAuth: includeAuth);
          response = await http
              .post(uri, headers: newHeaders, body: body != null ? jsonEncode(body) : null)
              .timeout(ApiConfig.timeout);
        } else {
          throw ApiException('Session expired. Please login again.', statusCode: 401);
        }
      }
      return await _handleResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      final l10n = await _resolveLocalizations();
      throw ApiException('${l10n.backendNetworkError}: $e');
    }
  }

  Future<dynamic> put(
    String endpoint, {
    Map<String, dynamic>? body,
    bool includeAuth = false,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint');
    final headers = await _getHeaders(includeAuth: includeAuth);
    try {
      var response = await http
          .put(uri, headers: headers, body: body != null ? jsonEncode(body) : null)
          .timeout(ApiConfig.timeout);
      if (response.statusCode == 401 && includeAuth) {
        final refreshed = await _refreshAccessToken();
        if (refreshed) {
          final newHeaders = await _getHeaders(includeAuth: includeAuth);
          response = await http
              .put(uri, headers: newHeaders, body: body != null ? jsonEncode(body) : null)
              .timeout(ApiConfig.timeout);
        } else {
          throw ApiException('Session expired. Please login again.', statusCode: 401);
        }
      }
      return await _handleResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      final l10n = await _resolveLocalizations();
      throw ApiException('${l10n.backendNetworkError}: $e');
    }
  }

  Future<dynamic> delete(
    String endpoint, {
    Map<String, dynamic>? body,
    bool includeAuth = false,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint');
    final headers = await _getHeaders(includeAuth: includeAuth);
    try {
      var response = await http
          .delete(uri, headers: headers, body: body != null ? jsonEncode(body) : null)
          .timeout(ApiConfig.timeout);
      if (response.statusCode == 401 && includeAuth) {
        final refreshed = await _refreshAccessToken();
        if (refreshed) {
          final newHeaders = await _getHeaders(includeAuth: includeAuth);
          response = await http
              .delete(uri, headers: newHeaders, body: body != null ? jsonEncode(body) : null)
              .timeout(ApiConfig.timeout);
        } else {
          throw ApiException('Session expired. Please login again.', statusCode: 401);
        }
      }
      return await _handleResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      final l10n = await _resolveLocalizations();
      throw ApiException('${l10n.backendNetworkError}: $e');
    }
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> register({
    required String email,
    required String username,
    required String password,
    required String passwordConfirm,
  }) async {
    return await post(ApiConfig.authRegister, body: {
      'email': email,
      'username': username,
      'password': password,
      'password_confirm': passwordConfirm,
    });
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    return await post(ApiConfig.authLogin, body: {'email': email, 'password': password});
  }

  Future<Map<String, dynamic>> requestPasswordReset({
    required String email,
    required String locale,
  }) async {
    return await post(ApiConfig.authPasswordResetRequest,
        body: {'email': email, 'locale': locale});
  }

  Future<void> logout() async {
    final refreshToken = await _storageService.getRefreshToken();
    if (refreshToken != null) {
      await post(ApiConfig.authLogout, body: {'refresh': refreshToken}, includeAuth: true);
    }
    await _storageService.clearAll();
  }

  Future<Map<String, dynamic>> getProfile() async {
    return await get(ApiConfig.authProfile, includeAuth: true);
  }

  Future<void> registerPushDevice({
    required String token,
    required String platform,
  }) async {
    await post(ApiConfig.pushDevicesRegister, includeAuth: true, body: {
      'token': token,
      'platform': platform,
    });
  }

  Future<void> unregisterPushDevice({required String token}) async {
    await post(ApiConfig.pushDevicesUnregister, includeAuth: true, body: {'token': token});
  }

  Future<Map<String, dynamic>> changeEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    return await post(ApiConfig.changeEmail, includeAuth: true, body: {
      'current_password': currentPassword,
      'new_email': newEmail,
    });
  }

  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    return await post(ApiConfig.changePassword, includeAuth: true, body: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  Future<dynamic> exportData() async {
    return await get(ApiConfig.dataExport, includeAuth: true);
  }

  Future<void> deleteAccount({required String password}) async {
    await delete(
      ApiConfig.deleteAccount,
      body: {'password': password},
      includeAuth: true,
    );
  }

  /// Send a bug report to the developer. A signed-in player is identified so
  /// they can be answered; a guest reports anonymously.
  Future<void> reportBug({
    required String message,
    required bool asGuest,
    String? appVersion,
    String? platform,
    String? locale,
  }) async {
    await post(ApiConfig.bugReport, includeAuth: !asGuest, body: {
      'message': message,
      if (appVersion != null) 'app_version': appVersion,
      if (platform != null) 'platform': platform,
      if (locale != null) 'locale': locale,
    });
  }

  // ── Game ──────────────────────────────────────────────────────────────────

  /// Public, so it is sent without the session: an expired token has no way
  /// to fail a request that never needed one.
  Future<List<dynamic>> getCategories() async {
    final result = await get(ApiConfig.categories);
    return result is List ? result : <dynamic>[];
  }

  /// The API contract this build speaks.
  ///
  /// v2 moved answer checking to the server, so a round no longer carries its
  /// own answer and guesses go to [submitGuess]. The server still serves v1 to
  /// installed apps that have not updated, which is why the version is explicit
  /// rather than assumed.
  static const String apiVersion = '2';

  /// The tail of the seen-track list is what matters for avoiding repeats, and
  /// the whole list would eventually outgrow the URL.
  static const int _maxExcludeIds = 200;

  Future<Map<String, dynamic>> getNextSong({
    bool mix = false,
    String? playlist,
    String? artist,
    int? artistDeezerId,
    List<String>? excludeIds,
  }) async {
    final params = <String, String>{'v': apiVersion};
    // All-genre: the server draws the round across every category. Sent
    // explicitly, because no filter at all still means the open catalogue.
    if (mix) params['mix'] = '1';
    if (playlist != null && playlist.isNotEmpty) params['playlist'] = playlist;
    // The Deezer ID pins the exact artist the player picked. The name is sent
    // too, as a fallback for favourites saved before the app recorded IDs.
    if (artistDeezerId != null) params['artist_id'] = artistDeezerId.toString();
    if (artist != null && artist.isNotEmpty) params['artist'] = artist;
    if (excludeIds != null && excludeIds.isNotEmpty) {
      final tail = excludeIds.length > _maxExcludeIds
          ? excludeIds.sublist(excludeIds.length - _maxExcludeIds)
          : excludeIds;
      params['exclude'] = tail.join(',');
    }
    return await get(ApiConfig.nextSong, includeAuth: true, queryParameters: params);
  }

  /// Ask the server whether a guess names the song being played.
  ///
  /// Comparing IDs locally is not good enough against the open catalogue: one
  /// song has many Deezer releases, so the album cut and the single are
  /// different IDs for the same answer. Passing [guessTrackId] as null means
  /// the player gave up, and the answer comes back either way.
  Future<Map<String, dynamic>> submitGuess({
    required String roundToken,
    String? guessTrackId,
  }) async {
    return await post(ApiConfig.guess, includeAuth: true, body: {
      'round_token': roundToken,
      if (guessTrackId != null) 'guess_track_id': guessTrackId,
    });
  }

  Future<List<dynamic>> searchArtists(String query) async {
    if (query.length < 2) return [];
    final result = await get(ApiConfig.artists, includeAuth: true,
        queryParameters: {'q': query});
    return result is List ? result : <dynamic>[];
  }

  Future<List<dynamic>> searchTracks(String query, {int limit = 20}) async {
    final result = await get(ApiConfig.searchTracks, includeAuth: true,
        queryParameters: {'q': query, 'limit': limit.toString()});
    return result is List ? result : <dynamic>[];
  }

  Future<Map<String, dynamic>> submitScore({
    String? genre,
    String artistFilter = '',
    String difficulty = 'medium',
    required int songsPlayed,
    required int songsCorrect,
    required int bestStreak,
    required int totalScore,
    String? sessionUuid,
    bool isPartial = false,
  }) async {
    return await post(ApiConfig.submitScore, includeAuth: true, body: {
      if (genre != null && genre.isNotEmpty) 'genre': genre,
      'artist_filter': artistFilter,
      'difficulty': difficulty,
      'songs_played': songsPlayed,
      'songs_correct': songsCorrect,
      'best_streak': bestStreak,
      'total_score': totalScore,
      if (sessionUuid != null) 'session_uuid': sessionUuid,
      if (isPartial) 'is_partial': true,
    });
  }

  Future<void> migrateGuestStats({
    required int bestScore,
    required int bestStreak,
    required int songsPlayed,
    required int songsCorrect,
  }) async {
    await post(ApiConfig.migrateGuestStats, includeAuth: true, body: {
      'best_score': bestScore,
      'best_streak': bestStreak,
      'songs_played': songsPlayed,
      'songs_correct': songsCorrect,
    });
  }

  Future<List<dynamic>> getTrendingArtists() async {
    final result = await get(ApiConfig.artistsTrending, includeAuth: true);
    return result is List ? result : <dynamic>[];
  }

  Future<List<dynamic>> getFavouriteArtists() async {
    final result = await get(ApiConfig.artistsFavourites, includeAuth: true);
    return result is List ? result : <dynamic>[];
  }

  Future<void> addFavouriteArtist(String artistName, {int? artistDeezerId}) async {
    await post(ApiConfig.artistsFavourites, includeAuth: true, body: {
      'artist_name': artistName,
      if (artistDeezerId != null) 'artist_deezer_id': artistDeezerId,
    });
  }

  Future<void> removeFavouriteArtist(String artistName) async {
    await delete(ApiConfig.artistFavouriteDetail(Uri.encodeComponent(artistName)),
        includeAuth: true);
  }

  Future<Map<String, dynamic>> getUserStats() async {
    return await get(ApiConfig.userStats, includeAuth: true);
  }

  Future<List<dynamic>> getLeaderboard({
    String? categoryId,
    String timeframe = 'daily',
    int limit = 50,
  }) async {
    final params = <String, String>{
      'timeframe': timeframe,
      'limit': limit.toString(),
    };
    if (categoryId != null) params['category'] = categoryId;
    final result = await get(ApiConfig.leaderboard, includeAuth: true, queryParameters: params);
    return result is List ? result : <dynamic>[];
  }

  Future<Map<String, dynamic>> refreshTrackPreview({required String trackId}) async {
    return await post(ApiConfig.trackRefreshPreview(trackId), includeAuth: true);
  }

  // ── Duel ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDuelElo() async {
    return await get(ApiConfig.duelElo, includeAuth: true);
  }

  Future<List<dynamic>> getDuelHistory({int limit = 20}) async {
    final result = await get(ApiConfig.duelHistory, includeAuth: true,
        queryParameters: {'limit': limit.toString()});
    return result is List ? result : <dynamic>[];
  }

  Future<Map<String, dynamic>> getDuelMatch(String matchId) async {
    return await get(ApiConfig.duelMatch(matchId), includeAuth: true);
  }

  Future<List<dynamic>> getDuelLeaderboard({int limit = 50}) async {
    final result = await get(ApiConfig.duelLeaderboard, includeAuth: true,
        queryParameters: {'limit': limit.toString()});
    return result is List ? result : <dynamic>[];
  }
}
