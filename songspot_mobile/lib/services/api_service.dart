import 'dart:convert';
import 'dart:typed_data';
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
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  String _extractFirstErrorMessage(Map<String, dynamic> body) {
    final possibleKeys = <String>['error', 'message', 'detail'];
    for (final key in possibleKeys) {
      final value = body[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is List && value.isNotEmpty && value.first is String) {
        final first = (value.first as String).trim();
        if (first.isNotEmpty) return first;
      }
    }

    for (final entry in body.entries) {
      final value = entry.value;
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
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
      final localeManuallySelected =
          prefs.getBool(_settingsLocaleManualKey) ?? false;
      final platformLanguageCode =
          WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      final languageCode = localeManuallySelected && savedLanguageCode != null
          ? savedLanguageCode
          : platformLanguageCode;

      final supported = AppLocalizations.supportedLocales
          .map((l) => l.languageCode)
          .toSet();
      final safeCode = supported.contains(languageCode) ? languageCode : 'en';
      return lookupAppLocalizations(Locale(safeCode));
    } catch (_) {
      return lookupAppLocalizations(const Locale('en'));
    }
  }

  num _numParam(Map<String, dynamic> params, String key, {num fallback = 0}) {
    final value = params[key];
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? fallback;
    return fallback;
  }

  String? _localizeBackendCode({
    required String code,
    required Map<String, dynamic> params,
    required AppLocalizations l10n,
  }) {
    switch (code) {
      case 'ROOM_LIMIT_REACHED':
        final maxRooms = _numParam(params, 'max_rooms', fallback: 0);
        if (maxRooms > 0) {
          return l10n.backendRoomLimitReachedWithLimit(maxRooms);
        }
        return l10n.backendRoomLimitReached;
      case 'DAILY_ROOM_CREATION_LIMIT_REACHED':
        final dailyLimit = _numParam(params, 'daily_limit', fallback: 0);
        if (dailyLimit > 0) {
          return l10n.backendDailyRoomCreationLimitReachedWithLimit(dailyLimit);
        }
        return l10n.backendDailyRoomCreationLimitReached;
      case 'ALREADY_IN_ROOM':
        return l10n.backendAlreadyInRoom;
      case 'NOT_IN_ROOM':
        return l10n.backendNotInRoom;
      case 'ONLY_HOST_CAN_RENAME_ROOM':
        return l10n.backendOnlyHostCanRenameRoom;
      case 'MUST_BE_IN_ROOM_TO_PLAY_GAME':
        return l10n.backendMustBeInRoomToPlayGame;
      case 'NO_SONG_AVAILABLE_TODAY':
        return l10n.backendNoSongAvailableToday;
      case 'NO_ACTIVE_GAME_SESSION':
        return l10n.backendNoActiveGameSession;
      case 'GAME_ALREADY_COMPLETED':
        return l10n.backendGameAlreadyCompleted;
      case 'RETRY_AFTER_LAST_SNIPPET_ONLY':
        return l10n.backendRetryAfterLastSnippetOnly;
      case 'RETRY_ALREADY_ACTIVE':
        return l10n.backendRetryAlreadyActive;
      case 'RETRY_NOT_PENDING_UNLOCK':
        return l10n.backendRetryNotPendingUnlock;
      case 'NO_RETRIES_REMAINING':
        return l10n.backendNoRetriesRemaining;
      case 'INVALID_RETRY_ACTION':
        final expected = params['expected_action']?.toString();
        if (expected != null && expected.isNotEmpty) {
          return l10n.backendInvalidRetryAction(expected);
        }
        return l10n.backendInvalidRetryActionUnknown;
      case 'INSUFFICIENT_COINS':
        final required = _numParam(params, 'required_coins', fallback: 0);
        if (required > 0) {
          return l10n.backendInsufficientCoinsWithCost(required);
        }
        return l10n.backendInsufficientCoins;
      case 'INVALID_CREDENTIALS':
        return l10n.backendInvalidCredentials;
      case 'REFRESH_TOKEN_REQUIRED':
        return l10n.backendRefreshTokenRequired;
      case 'INVALID_OR_EXPIRED_REFRESH_TOKEN':
        return l10n.backendInvalidOrExpiredRefreshToken;
      case 'INVALID_TOKEN':
        return l10n.backendInvalidToken;
      case 'INVALID_PASSWORD':
        return l10n.backendInvalidPassword;
      case 'INVALID_CURRENT_PASSWORD':
        return l10n.backendInvalidCurrentPassword;
      case 'MISSING_REQUIRED_FIELDS':
        return l10n.backendMissingRequiredFields;
      case 'INVALID_STORE':
        return l10n.backendInvalidStore;
      case 'PURCHASE_PROCESSING':
        return l10n.backendPurchaseProcessing;
      case 'UNKNOWN_OR_INACTIVE_PRODUCT':
        final productId = params['product_id']?.toString();
        if (productId != null && productId.isNotEmpty) {
          return l10n.backendUnknownOrInactiveProduct(productId);
        }
        return l10n.backendUnknownOrInactiveProductUnknown;
      case 'RECEIPT_VERIFICATION_FAILED':
        return l10n.backendReceiptVerificationFailed;
    }
    return null;
  }

  String _localizeBackendMessageFallback(
    String message,
    AppLocalizations l10n,
  ) {
    final cleaned = message.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    if (cleaned.isEmpty) return cleaned;

    if (cleaned.startsWith('Room limit reached')) {
      return l10n.backendRoomLimitReached;
    }
    if (cleaned.startsWith('Daily room creation limit reached')) {
      return l10n.backendDailyRoomCreationLimitReached;
    }
    if (cleaned == 'You are already in this room') {
      return l10n.backendAlreadyInRoom;
    }
    if (cleaned == 'You are not in this room') {
      return l10n.backendNotInRoom;
    }
    if (cleaned == 'Only the host can rename the room.') {
      return l10n.backendOnlyHostCanRenameRoom;
    }
    if (cleaned == 'Room not found.') {
      return l10n.backendRoomNotFound;
    }
    if (cleaned == 'Insufficient coins') {
      return l10n.backendInsufficientCoins;
    }
    if (cleaned == 'No retries remaining') {
      return l10n.backendNoRetriesRemaining;
    }
    if (cleaned == 'Retry is only available after reaching the last snippet') {
      return l10n.backendRetryAfterLastSnippetOnly;
    }
    if (cleaned == 'Game already completed' ||
        cleaned == 'Game already completed.') {
      return l10n.backendGameAlreadyCompleted;
    }
    if (cleaned ==
            'No active game session. Start by calling GET /daily-game/' ||
        cleaned == 'No active game session.') {
      return l10n.backendNoActiveGameSession;
    }
    if (cleaned == 'No song available for today') {
      return l10n.backendNoSongAvailableToday;
    }
    if (cleaned == 'This pack is not owned by the room') {
      return l10n.backendPackNotOwnedByRoom;
    }
    if (cleaned == 'Pack has no tracks') {
      return l10n.backendPackHasNoTracks;
    }
    if (cleaned == 'No active pack session. Start with GET bundle.' ||
        cleaned == 'No active pack session.') {
      return l10n.backendNoActivePackSession;
    }
    if (cleaned == 'Pack already completed' ||
        cleaned == 'Pack session already completed.') {
      return l10n.backendPackAlreadyCompleted;
    }
    if (cleaned == 'Track not found.' || cleaned == 'Pack track not found') {
      return l10n.backendTrackNotFound;
    }
    if (cleaned == 'Already guessed for this stage') {
      return l10n.backendAlreadyGuessedForStage;
    }
    if (cleaned == 'room_id is required') {
      return l10n.backendRoomIdRequired;
    }
    if (cleaned == 'Invalid password.') {
      return l10n.backendInvalidPassword;
    }
    if (cleaned == 'Invalid current password.') {
      return l10n.backendInvalidCurrentPassword;
    }
    if (cleaned.startsWith('Invalid date format. Use YYYY-MM-DD.')) {
      return l10n.backendInvalidDateFormat;
    }
    if (cleaned == 'This date is not yet in history.') {
      return l10n.backendDateNotInHistory;
    }
    if (cleaned == 'No song found for this date.') {
      return l10n.backendNoSongFoundForDate;
    }
    if (cleaned == 'No pack track found for this date.') {
      return l10n.backendNoPackTrackForDate;
    }
    if (cleaned == 'No active account found with the given credentials') {
      return l10n.backendInvalidCredentials;
    }

    return cleaned;
  }

  Future<dynamic> _handleResponse(http.Response response) async {
    final statusCode = response.statusCode;

    if (statusCode >= 200 && statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    } else {
      String message = 'Request failed with status: $statusCode';
      Map<String, dynamic>? errors;
      String? rawMessage;
      String? errorCode;
      Map<String, dynamic>? errorParams;

      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          final extractedCode = body['error_code'];
          if (extractedCode is String && extractedCode.trim().isNotEmpty) {
            errorCode = extractedCode.trim();
          }
          final extractedParams = body['params'];
          if (extractedParams is Map) {
            errorParams = Map<String, dynamic>.from(extractedParams);
          }

          final extracted = _extractFirstErrorMessage(body);
          if (extracted.isNotEmpty) {
            rawMessage = extracted;
            final l10n = await _resolveLocalizations();
            if (errorCode != null) {
              final localizedByCode = _localizeBackendCode(
                code: errorCode,
                params: errorParams ?? const {},
                l10n: l10n,
              );
              if (localizedByCode != null && localizedByCode.isNotEmpty) {
                message = localizedByCode;
              } else {
                message = _localizeBackendMessageFallback(extracted, l10n);
              }
            } else {
              message = _localizeBackendMessageFallback(extracted, l10n);
            }
          }
          errors = body;
        }
      } catch (e) {
        // Could not parse error response
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
    } catch (e) {
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
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}$endpoint',
    ).replace(queryParameters: queryParameters);
    final headers = await _getHeaders(includeAuth: includeAuth);

    try {
      var response = await http
          .get(uri, headers: headers)
          .timeout(ApiConfig.timeout);

      if (response.statusCode == 401 && includeAuth) {
        final refreshed = await _refreshAccessToken();
        if (refreshed) {
          final newHeaders = await _getHeaders(includeAuth: includeAuth);
          response = await http
              .get(uri, headers: newHeaders)
              .timeout(ApiConfig.timeout);
        } else {
          throw ApiException(
            'Session expired. Please login again.',
            statusCode: 401,
          );
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
          .post(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(ApiConfig.timeout);

      if (response.statusCode == 401 && includeAuth) {
        final refreshed = await _refreshAccessToken();
        if (refreshed) {
          final newHeaders = await _getHeaders(includeAuth: includeAuth);
          response = await http
              .post(
                uri,
                headers: newHeaders,
                body: body != null ? jsonEncode(body) : null,
              )
              .timeout(ApiConfig.timeout);
        } else {
          throw ApiException(
            'Session expired. Please login again.',
            statusCode: 401,
          );
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
          .put(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(ApiConfig.timeout);

      if (response.statusCode == 401 && includeAuth) {
        final refreshed = await _refreshAccessToken();
        if (refreshed) {
          final newHeaders = await _getHeaders(includeAuth: includeAuth);
          response = await http
              .put(
                uri,
                headers: newHeaders,
                body: body != null ? jsonEncode(body) : null,
              )
              .timeout(ApiConfig.timeout);
        } else {
          throw ApiException(
            'Session expired. Please login again.',
            statusCode: 401,
          );
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
      var response = await http
          .delete(uri, headers: headers)
          .timeout(ApiConfig.timeout);

      if (response.statusCode == 401 && includeAuth) {
        final refreshed = await _refreshAccessToken();
        if (refreshed) {
          final newHeaders = await _getHeaders(includeAuth: includeAuth);
          response = await http
              .delete(uri, headers: newHeaders)
              .timeout(ApiConfig.timeout);
        } else {
          throw ApiException(
            'Session expired. Please login again.',
            statusCode: 401,
          );
        }
      }

      return await _handleResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      final l10n = await _resolveLocalizations();
      throw ApiException('${l10n.backendNetworkError}: $e');
    }
  }

  // Pack methods
  Future<List<dynamic>> getPacks({required String roomId}) async {
    final response = await get(
      ApiConfig.packs,
      includeAuth: true,
      queryParameters: {'room_id': roomId},
    );
    return response as List<dynamic>;
  }

  Future<Map<String, dynamic>> getPackDetail({
    required String roomId,
    required String packId,
  }) async {
    final response = await get(
      ApiConfig.packDetail(packId),
      includeAuth: true,
      queryParameters: {'room_id': roomId},
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> purchasePack({
    required String roomId,
    required String packId,
  }) async {
    final response = await post(
      ApiConfig.packPurchase(packId),
      includeAuth: true,
      body: {'room_id': roomId},
    );
    return response as Map<String, dynamic>;
  }

  Future<List<dynamic>> getMyPacks({required String roomId}) async {
    final response = await get(
      ApiConfig.packsMy,
      includeAuth: true,
      queryParameters: {'room_id': roomId},
    );
    return response as List<dynamic>;
  }

  Future<Map<String, dynamic>> refreshTrackPreview({
    required String trackId,
  }) async {
    final response = await post(
      ApiConfig.trackRefreshPreview(trackId),
      includeAuth: true,
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getPackBundle({
    required String roomId,
    required String packId,
  }) async {
    final response = await get(
      ApiConfig.packBundle(roomId, packId),
      includeAuth: true,
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> skipPackBundle({
    required String roomId,
    required String packId,
  }) async {
    final response = await post(
      ApiConfig.packBundleSkip(roomId, packId),
      includeAuth: true,
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> guessPackBundle({
    required String roomId,
    required String packId,
    required String trackId,
  }) async {
    final response = await post(
      ApiConfig.packBundleGuess(roomId, packId),
      includeAuth: true,
      body: {'track_id': trackId},
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> activatePackBundleRetry({
    required String roomId,
    required String packId,
    required String action,
  }) async {
    final response = await post(
      ApiConfig.packBundleRetry(roomId, packId),
      includeAuth: true,
      body: {'action': action},
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getPackBundleLeaderboard({
    required String roomId,
    required String packId,
  }) async {
    final response = await get(
      ApiConfig.packBundleLeaderboard(roomId, packId),
      includeAuth: true,
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getPackBundleMessages({
    required String roomId,
    required String packId,
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await get(
      ApiConfig.packBundleMessages(roomId, packId),
      queryParameters: {'limit': limit.toString(), 'offset': offset.toString()},
      includeAuth: true,
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendPackBundleMessage({
    required String roomId,
    required String packId,
    required String message,
  }) async {
    final response = await post(
      ApiConfig.packBundleMessages(roomId, packId),
      body: {'message': message},
      includeAuth: true,
    );
    return response as Map<String, dynamic>;
  }

  // Auth methods
  Future<Map<String, dynamic>> register({
    required String email,
    required String username,
    required String password,
    required String passwordConfirm,
  }) async {
    return await post(
      ApiConfig.authRegister,
      body: {
        'email': email,
        'username': username,
        'password': password,
        'password_confirm': passwordConfirm,
      },
    );
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    return await post(
      ApiConfig.authLogin,
      body: {'email': email, 'password': password},
    );
  }

  Future<void> logout() async {
    final refreshToken = await _storageService.getRefreshToken();
    if (refreshToken != null) {
      await post(
        ApiConfig.authLogout,
        body: {'refresh': refreshToken},
        includeAuth: true,
      );
    }
    await _storageService.clearAll();
  }

  Future<Map<String, dynamic>> getProfile() async {
    return await get(ApiConfig.authProfile, includeAuth: true);
  }

  Future<void> registerPushDevice({
    required String token,
    required String platform,
    bool dailySongEnabled = true,
    bool messagesEnabled = true,
  }) async {
    await post(
      ApiConfig.pushDevicesRegister,
      includeAuth: true,
      body: {
        'token': token,
        'platform': platform,
        'daily_song_enabled': dailySongEnabled,
        'messages_enabled': messagesEnabled,
      },
    );
  }

  Future<void> unregisterPushDevice({required String token}) async {
    await post(
      ApiConfig.pushDevicesUnregister,
      includeAuth: true,
      body: {'token': token},
    );
  }

  // Room methods
  Future<Map<String, dynamic>> createRoom() async {
    return await post(ApiConfig.roomsCreate, body: {}, includeAuth: true);
  }

  Future<Map<String, dynamic>> joinRoom(String roomCode) async {
    return await post(
      ApiConfig.roomsJoin,
      body: {'room_code': roomCode},
      includeAuth: true,
    );
  }

  Future<List<dynamic>> getMyRooms() async {
    return await get(ApiConfig.roomsMyRooms, includeAuth: true);
  }

  Future<Map<String, dynamic>> getRoomDetails(String roomId) async {
    return await get(ApiConfig.roomsDetail(roomId), includeAuth: true);
  }

  Future<void> leaveRoom(String roomId) async {
    await post(ApiConfig.roomsLeave(roomId), includeAuth: true);
  }

  Future<Map<String, dynamic>> renameRoom(String roomId, String? name) async {
    return await put(
      ApiConfig.roomsRename(roomId),
      body: {'name': name ?? ''},
      includeAuth: true,
    );
  }

  Future<Map<String, dynamic>> getDailySong(String roomId) async {
    return await get(ApiConfig.roomsDailySong(roomId), includeAuth: true);
  }

  // Game methods
  Future<Map<String, dynamic>> startGameSession(String roomId) async {
    return await get(ApiConfig.dailyGame(roomId), includeAuth: true);
  }

  Future<Map<String, dynamic>> skipSnippet(String roomId) async {
    return await post(ApiConfig.dailyGameSkip(roomId), includeAuth: true);
  }

  Future<Map<String, dynamic>> submitGuess({
    required String roomId,
    required String trackId,
  }) async {
    return await post(
      ApiConfig.dailyGameGuess(roomId),
      body: {'track_id': trackId},
      includeAuth: true,
    );
  }

  Future<Map<String, dynamic>> activateDailyRetry({
    required String roomId,
    required String action,
  }) async {
    return await post(
      ApiConfig.dailyGameRetry(roomId),
      body: {'action': action},
      includeAuth: true,
    );
  }

  Future<Map<String, dynamic>> getLeaderboard(String roomId) async {
    return await get(ApiConfig.dailyGameLeaderboard(roomId), includeAuth: true);
  }

  // Chat methods
  Future<Map<String, dynamic>> getMessages({
    required String roomId,
    int limit = 50,
    int offset = 0,
  }) async {
    return await get(
      ApiConfig.roomMessages(roomId),
      queryParameters: {'limit': limit.toString(), 'offset': offset.toString()},
      includeAuth: true,
    );
  }

  Future<Map<String, dynamic>> sendMessage({
    required String roomId,
    required String message,
  }) async {
    return await post(
      ApiConfig.roomMessages(roomId),
      body: {'message': message},
      includeAuth: true,
    );
  }

  // Track search
  Future<List<dynamic>> searchTracks(String query, {int limit = 25}) async {
    final safeLimit = limit.clamp(1, 50);
    return await get(
      ApiConfig.searchTracks,
      queryParameters: {'q': query, 'limit': safeLimit.toString()},
      includeAuth: true,
    );
  }

  // IAP / Coin shop methods
  Future<List<dynamic>> getCoinProducts() async {
    return await get(ApiConfig.coinProducts, includeAuth: true);
  }

  Future<Map<String, dynamic>> verifyIAP({
    required String store,
    required String productId,
    required String receiptData,
    required String transactionId,
  }) async {
    return await post(
      ApiConfig.iapVerify,
      body: {
        'store': store,
        'product_id': productId,
        'receipt_data': receiptData,
        'transaction_id': transactionId,
      },
      includeAuth: true,
    );
  }

  Future<Map<String, dynamic>> activateNoAdsPass() async {
    return await post(ApiConfig.noAdsActivate, includeAuth: true);
  }

  Future<Map<String, dynamic>> claimRewardedAd({
    String placement = 'game_result',
  }) async {
    return await post(
      ApiConfig.adsRewardClaim,
      body: {'placement': placement},
      includeAuth: true,
    );
  }

  Future<Map<String, dynamic>> getRewardedAdStatus() async {
    return await get(ApiConfig.adsRewardStatus, includeAuth: true);
  }

  // Hint methods
  Future<Map<String, dynamic>> purchaseDailyGameHint({
    required String roomId,
    required String hintType,
  }) async {
    return await post(
      ApiConfig.dailyGameHint(roomId),
      body: {'hint_type': hintType},
      includeAuth: true,
    );
  }

  Future<Map<String, dynamic>> purchasePackBundleHint({
    required String roomId,
    required String packId,
    required String hintType,
  }) async {
    return await post(
      ApiConfig.packBundleHint(roomId, packId),
      body: {'hint_type': hintType},
      includeAuth: true,
    );
  }

  // Account management methods
  Future<Map<String, dynamic>> changeEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    return await post(
      ApiConfig.changeEmail,
      body: {'current_password': currentPassword, 'new_email': newEmail},
      includeAuth: true,
    );
  }

  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmNewPassword,
  }) async {
    return await post(
      ApiConfig.changePassword,
      body: {
        'current_password': currentPassword,
        'new_password': newPassword,
        'confirm_new_password': confirmNewPassword,
      },
      includeAuth: true,
    );
  }

  /// Returns the raw JSON bytes of the data export file.
  Future<Uint8List> exportData() async {
    final token = await _storageService.getAccessToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.dataExport}');
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    try {
      final response = await http
          .get(uri, headers: headers)
          .timeout(ApiConfig.timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      } else {
        throw ApiException(
          'Export failed with status: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e');
    }
  }

  Future<void> deleteAccount({required String password}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.deleteAccount}');
    final token = await _storageService.getAccessToken();
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    try {
      final response = await http
          .delete(
            uri,
            headers: headers,
            body: jsonEncode({'password': password}),
          )
          .timeout(ApiConfig.timeout);

      if (response.statusCode == 204) return;
      _handleResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e');
    }
  }

  Future<Map<String, dynamic>> getRoomHistory(
    String roomId, {
    int limit = 30,
    int offset = 0,
  }) async {
    return await get(
      ApiConfig.roomHistory(roomId),
      includeAuth: true,
      queryParameters: {'limit': limit.toString(), 'offset': offset.toString()},
    );
  }

  Future<Map<String, dynamic>> getRoomHistoryDetail(
    String roomId,
    String date,
  ) async {
    return await get(
      ApiConfig.roomHistoryDetail(roomId, date),
      includeAuth: true,
    );
  }

  Future<Map<String, dynamic>> getPackBundleHistory(
    String roomId,
    String packId, {
    int limit = 30,
    int offset = 0,
  }) async {
    return await get(
      ApiConfig.packBundleHistory(roomId, packId),
      includeAuth: true,
      queryParameters: {'limit': limit.toString(), 'offset': offset.toString()},
    );
  }

  Future<Map<String, dynamic>> getPackBundleHistoryDetail(
    String roomId,
    String packId,
    String date,
  ) async {
    return await get(
      ApiConfig.packBundleHistoryDetail(roomId, packId, date),
      includeAuth: true,
    );
  }
}
