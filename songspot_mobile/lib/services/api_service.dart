import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'storage_service.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? errors;

  ApiException(this.message, {this.statusCode, this.errors});

  @override
  String toString() => message;
}

class ApiService {
  final StorageService _storageService = StorageService();
  bool _isRefreshing = false;

  Future<Map<String, String>> _getHeaders({bool includeAuth = false}) async {
    final headers = {
      'Content-Type': 'application/json',
    };

    if (includeAuth) {
      final token = await _storageService.getAccessToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  dynamic _handleResponse(http.Response response) {
    final statusCode = response.statusCode;

    if (statusCode >= 200 && statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    } else {
      String message = 'Request failed with status: $statusCode';
      Map<String, dynamic>? errors;

      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          if (body.containsKey('error')) {
            message = body['error'] as String;
          } else if (body.containsKey('message')) {
            message = body['message'] as String;
          } else if (body.containsKey('detail')) {
            message = body['detail'] as String;
          }
          errors = body;
        }
      } catch (e) {
        // Could not parse error response
      }

      throw ApiException(message, statusCode: statusCode, errors: errors);
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
    final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint')
        .replace(queryParameters: queryParameters);
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
          throw ApiException('Session expired. Please login again.', statusCode: 401);
        }
      }

      return _handleResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e');
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
          throw ApiException('Session expired. Please login again.', statusCode: 401);
        }
      }

      return _handleResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e');
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
          throw ApiException('Session expired. Please login again.', statusCode: 401);
        }
      }

      return _handleResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e');
    }
  }

  Future<dynamic> delete(
    String endpoint, {
    bool includeAuth = false,
  }) async {
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
          throw ApiException('Session expired. Please login again.', statusCode: 401);
        }
      }

      return _handleResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e');
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

  Future<Map<String, dynamic>> refreshTrackPreview({required String trackId}) async {
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
      queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
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
      body: {
        'email': email,
        'password': password,
      },
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

  Future<void> unregisterPushDevice({
    required String token,
  }) async {
    await post(
      ApiConfig.pushDevicesUnregister,
      includeAuth: true,
      body: {'token': token},
    );
  }

  // Room methods
  Future<Map<String, dynamic>> createRoom() async {
    return await post(
      ApiConfig.roomsCreate,
      body: {},
      includeAuth: true,
    );
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
      body: {
        'track_id': trackId,
      },
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
      queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
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
  Future<List<dynamic>> searchTracks(String query) async {
    return await get(
      ApiConfig.searchTracks,
      queryParameters: {'q': query},
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
      body: {
        'current_password': currentPassword,
        'new_email': newEmail,
      },
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
      final response = await http.get(uri, headers: headers).timeout(ApiConfig.timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      } else {
        throw ApiException('Export failed with status: ${response.statusCode}', statusCode: response.statusCode);
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
      queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
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
      queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
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
