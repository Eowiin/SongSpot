import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _storage = FlutterSecureStorage();

  // Keys
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userIdKey = 'user_id';
  static const String _userEmailKey = 'user_email';
  static const String _usernameKey = 'username';

  // Token methods
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<String?> getAccessToken() async {
    return await _storage.read(key: _accessTokenKey);
  }

  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _refreshTokenKey);
  }

  Future<void> deleteTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  // User methods
  Future<void> saveUser({
    required String id,
    required String email,
    required String username,
  }) async {
    await _storage.write(key: _userIdKey, value: id);
    await _storage.write(key: _userEmailKey, value: email);
    await _storage.write(key: _usernameKey, value: username);
  }

  Future<Map<String, String>?> getUser() async {
    final id = await _storage.read(key: _userIdKey);
    final email = await _storage.read(key: _userEmailKey);
    final username = await _storage.read(key: _usernameKey);

    if (id != null && email != null && username != null) {
      return {
        'id': id,
        'email': email,
        'username': username,
      };
    }
    return null;
  }

  Future<void> deleteUser() async {
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _userEmailKey);
    await _storage.delete(key: _usernameKey);
  }

  // Clear all data
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  // ── Guest mode ───────────────────────────────────────────────────────────

  static const String _guestModeKey = 'guest_mode';
  static const String _guestBestScoreKey = 'guest_best_score';
  static const String _guestBestStreakKey = 'guest_best_streak';
  static const String _guestSongsPlayedKey = 'guest_songs_played';
  static const String _guestSongsCorrectKey = 'guest_songs_correct';

  Future<void> setGuestMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_guestModeKey, value);
  }

  Future<bool> isGuestMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_guestModeKey) ?? false;
  }

  Future<void> saveGuestStats({
    required int bestScore,
    required int bestStreak,
    required int songsPlayed,
    required int songsCorrect,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_guestBestScoreKey, bestScore);
    await prefs.setInt(_guestBestStreakKey, bestStreak);
    await prefs.setInt(_guestSongsPlayedKey, songsPlayed);
    await prefs.setInt(_guestSongsCorrectKey, songsCorrect);
  }

  Future<Map<String, int>> getGuestStats() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'best_score': prefs.getInt(_guestBestScoreKey) ?? 0,
      'best_streak': prefs.getInt(_guestBestStreakKey) ?? 0,
      'songs_played': prefs.getInt(_guestSongsPlayedKey) ?? 0,
      'songs_correct': prefs.getInt(_guestSongsCorrectKey) ?? 0,
    };
  }

  Future<void> clearGuestData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_guestModeKey);
    await prefs.remove(_guestBestScoreKey);
    await prefs.remove(_guestBestStreakKey);
    await prefs.remove(_guestSongsPlayedKey);
    await prefs.remove(_guestSongsCorrectKey);
  }
}
