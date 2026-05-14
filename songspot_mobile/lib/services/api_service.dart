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
  final StorageService _storageService = StorageService();
  bool _isRefreshing = false;
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
        final localized = _localizeBackendCode(l10n, errorCode!);
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

  Future<bool> _refreshAccessToken() async {
    if (_isRefreshing) return false;
    _isRefreshing = true;
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
    } finally {
      _isRefreshing = false;
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

  Future<dynamic> delete(String endpoint, {bool includeAuth = false}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint');
    final headers = await _getHeaders(includeAuth: includeAuth);
    try {
      var response = await http.delete(uri, headers: headers).timeout(ApiConfig.timeout);
      if (response.statusCode == 401 && includeAuth) {
        final refreshed = await _refreshAccessToken();
        if (refreshed) {
          final newHeaders = await _getHeaders(includeAuth: includeAuth);
          response = await http.delete(uri, headers: newHeaders).timeout(ApiConfig.timeout);
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

  Future<Map<String, dynamic>> changeEmail({required String newEmail}) async {
    return await post(ApiConfig.changeEmail, includeAuth: true, body: {'new_email': newEmail});
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

  Future<void> deleteAccount() async {
    await delete(ApiConfig.deleteAccount, includeAuth: true);
  }

  // ── Game ──────────────────────────────────────────────────────────────────

  Future<List<dynamic>> getCategories() async {
    return await get(ApiConfig.categories, includeAuth: true);
  }

  Future<Map<String, dynamic>> getNextSong({
    String? genre,
    String? artist,
    List<String>? excludeIds,
  }) async {
    final params = <String, String>{};
    if (genre != null && genre.isNotEmpty) params['genre'] = genre;
    if (artist != null && artist.isNotEmpty) params['artist'] = artist;
    if (excludeIds != null && excludeIds.isNotEmpty) {
      params['exclude'] = excludeIds.join(',');
    }
    return await get(ApiConfig.nextSong, includeAuth: true, queryParameters: params);
  }

  Future<List<dynamic>> searchArtists(String query) async {
    if (query.length < 2) return [];
    return await get(ApiConfig.artists, includeAuth: true,
        queryParameters: {'q': query});
  }

  Future<List<dynamic>> searchTracks(String query, {int limit = 20}) async {
    return await get(ApiConfig.searchTracks, includeAuth: true,
        queryParameters: {'q': query, 'limit': limit.toString()});
  }

  Future<Map<String, dynamic>> submitScore({
    String? genre,
    String artistFilter = '',
    String difficulty = 'medium',
    required int songsPlayed,
    required int songsCorrect,
    required int bestStreak,
    required int totalScore,
  }) async {
    return await post(ApiConfig.submitScore, includeAuth: true, body: {
      if (genre != null && genre.isNotEmpty) 'genre': genre,
      'artist_filter': artistFilter,
      'difficulty': difficulty,
      'songs_played': songsPlayed,
      'songs_correct': songsCorrect,
      'best_streak': bestStreak,
      'total_score': totalScore,
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
    return await get(ApiConfig.artistsTrending, includeAuth: true);
  }

  Future<List<dynamic>> getFavouriteArtists() async {
    return await get(ApiConfig.artistsFavourites, includeAuth: true);
  }

  Future<void> addFavouriteArtist(String artistName) async {
    await post(ApiConfig.artistsFavourites, includeAuth: true,
        body: {'artist_name': artistName});
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
    return await get(ApiConfig.leaderboard, includeAuth: true, queryParameters: params);
  }

  Future<Map<String, dynamic>> refreshTrackPreview({required String trackId}) async {
    return await post(ApiConfig.trackRefreshPreview(trackId), includeAuth: true);
  }
}
