import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/push_notification_service.dart';
import '../services/storage_service.dart';

enum AuthStatus { initial, authenticated, unauthenticated, loading }

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();
  final PushNotificationService _pushNotificationService = PushNotificationService();

  AuthStatus _status = AuthStatus.initial;
  User? _user;
  String? _errorMessage;

  AuthStatus get status => _status;
  User? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  /// Check if user is already logged in and fetch fresh profile from API.
  /// Always fetches from the backend so dynamic fields like coins are current.
  /// Falls back to local storage only if the network call fails.
  Future<void> checkAuthStatus() async {
    try {
      final token = await _storageService.getAccessToken();
      if (token == null) {
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return;
      }

      try {
        // Fetch fresh profile from API — includes coins and all dynamic fields
        final profileData = await _apiService.getProfile();
        _user = User.fromJson(profileData);
      } catch (_) {
        // Network unavailable — fall back to local storage (coins may be stale)
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
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }

  /// Register a new user
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

      // Save tokens
      final tokens = response['tokens'] as Map<String, dynamic>;
      await _storageService.saveTokens(
        tokens['access'] as String,
        tokens['refresh'] as String,
      );

      // Save user
      final userData = response['user'] as Map<String, dynamic>;
      _user = User.fromJson(userData);
      await _storageService.saveUser(
        id: _user!.id,
        email: _user!.email,
        username: _user!.username,
      );

      _status = AuthStatus.authenticated;
      await _pushNotificationService.syncTokenWithBackend();
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  /// Login user
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    try {
      _status = AuthStatus.loading;
      _errorMessage = null;
      notifyListeners();

      final response = await _apiService.login(
        email: email,
        password: password,
      );

      // Save tokens
      final tokens = response['tokens'] as Map<String, dynamic>;
      await _storageService.saveTokens(
        tokens['access'] as String,
        tokens['refresh'] as String,
      );

      // Save user
      final userData = response['user'] as Map<String, dynamic>;
      _user = User.fromJson(userData);
      await _storageService.saveUser(
        id: _user!.id,
        email: _user!.email,
        username: _user!.username,
      );

      _status = AuthStatus.authenticated;
      await _pushNotificationService.syncTokenWithBackend();
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  /// Logout user
  Future<void> logout() async {
    try {
      await _pushNotificationService.unregisterCurrentToken();
    } catch (e) {
      // Continue logout even if push cleanup fails
    }

    try {
      await _apiService.logout();
    } catch (e) {
      await _storageService.clearAll();
    }

    _user = null;
    _status = AuthStatus.unauthenticated;
    _errorMessage = null;
    notifyListeners();
  }

  /// Update the user's coin balance in memory and notify listeners.
  /// Called after a successful IAP purchase — no extra API call needed since
  /// the backend already returned the correct new balance.
  void updateCoinsBalance(int newBalance) {
    if (_user == null) return;
    _user = User(
      id: _user!.id,
      email: _user!.email,
      username: _user!.username,
      coins: newBalance,
    );
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
