import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/push_notification_service.dart';
import '../services/storage_service.dart';

enum AuthStatus { initial, authenticated, unauthenticated, guest, loading }

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();
  final PushNotificationService _pushNotificationService =
      PushNotificationService();

  AuthStatus _status = AuthStatus.initial;
  User? _user;
  String? _errorMessage;

  AuthStatus get status => _status;
  User? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isGuest => _status == AuthStatus.guest;

  /// Check if user is already logged in and fetch fresh profile from API.
  /// Falls back to cached user data if network unavailable.
  /// If no token, checks for a persisted guest session.
  Future<void> checkAuthStatus() async {
    try {
      final token = await _storageService.getAccessToken();
      if (token != null) {
        try {
          final profileData = await _apiService.getProfile();
          _user = User.fromJson(profileData);
        } catch (_) {
          final userData = await _storageService.getUser();
          if (userData == null) {
            _status = AuthStatus.unauthenticated;
            notifyListeners();
            return;
          }
          _user = User.fromJson(userData);
        }
        _status = AuthStatus.authenticated;
        await _pushNotificationService.syncTokenWithBackend();
        notifyListeners();
        return;
      }

      final guestMode = await _storageService.isGuestMode();
      if (guestMode) {
        _status = AuthStatus.guest;
        _user = null;
        notifyListeners();
        return;
      }

      _status = AuthStatus.unauthenticated;
      notifyListeners();
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }

  /// Enter guest mode — persisted so reopening the app skips the login screen.
  Future<void> continueAsGuest() async {
    await _storageService.setGuestMode(true);
    _status = AuthStatus.guest;
    _user = null;
    notifyListeners();
  }

  /// Refresh the authenticated user's profile from backend.
  Future<void> refreshProfile({bool notify = true}) async {
    if (_status != AuthStatus.authenticated) return;
    try {
      final profileData = await _apiService.getProfile();
      _user = User.fromJson(profileData);
      if (notify) notifyListeners();
    } catch (_) {}
  }

  /// Register a new user, migrating any guest stats afterward.
  Future<bool> register({
    required String email,
    required String username,
    required String password,
    required String passwordConfirm,
  }) async {
    try {
      _status = AuthStatus.loading;
      _errorMessage = null;
      notifyListeners();

      final response = await _apiService.register(
        email: email,
        username: username,
        password: password,
        passwordConfirm: passwordConfirm,
      );

      final tokens = response['tokens'] as Map<String, dynamic>;
      await _storageService.saveTokens(
        tokens['access'] as String,
        tokens['refresh'] as String,
      );

      final userData = response['user'] as Map<String, dynamic>;
      _user = User.fromJson(userData);
      await _storageService.saveUser(
        id: _user!.id,
        email: _user!.email,
        username: _user!.username,
      );

      _status = AuthStatus.authenticated;
      await _pushNotificationService.syncTokenWithBackend();
      await _migrateGuestStatsIfNeeded();

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  /// Login user, migrating any guest stats afterward.
  Future<bool> login({required String email, required String password}) async {
    try {
      _status = AuthStatus.loading;
      _errorMessage = null;
      notifyListeners();

      final response = await _apiService.login(
        email: email,
        password: password,
      );

      final tokens = response['tokens'] as Map<String, dynamic>;
      await _storageService.saveTokens(
        tokens['access'] as String,
        tokens['refresh'] as String,
      );

      final userData = response['user'] as Map<String, dynamic>;
      _user = User.fromJson(userData);
      await _storageService.saveUser(
        id: _user!.id,
        email: _user!.email,
        username: _user!.username,
      );

      _status = AuthStatus.authenticated;
      await _pushNotificationService.syncTokenWithBackend();
      await _migrateGuestStatsIfNeeded();

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  /// Logout — works for both authenticated users and guests.
  Future<void> logout() async {
    if (_status == AuthStatus.guest) {
      await _storageService.clearGuestData();
      _user = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = null;
      notifyListeners();
      return;
    }

    try {
      await _pushNotificationService.unregisterCurrentToken();
    } catch (_) {}

    try {
      await _apiService.logout();
    } catch (_) {
      await _storageService.clearAll();
    }

    _user = null;
    _status = AuthStatus.unauthenticated;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _migrateGuestStatsIfNeeded() async {
    final guestStats = await _storageService.getGuestStats();
    if (guestStats['songs_played']! > 0) {
      try {
        await _apiService.migrateGuestStats(
          bestScore: guestStats['best_score']!,
          bestStreak: guestStats['best_streak']!,
          songsPlayed: guestStats['songs_played']!,
          songsCorrect: guestStats['songs_correct']!,
        );
      } catch (_) {}
    }
    await _storageService.clearGuestData();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
