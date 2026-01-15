import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

enum AuthStatus { initial, authenticated, unauthenticated, loading }

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();

  AuthStatus _status = AuthStatus.initial;
  User? _user;
  String? _errorMessage;

  AuthStatus get status => _status;
  User? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  /// Check if user is already logged in
  Future<void> checkAuthStatus() async {
    try {
      final token = await _storageService.getAccessToken();
      if (token != null) {
        final userData = await _storageService.getUser();
        if (userData != null) {
          _user = User.fromJson(userData);
          _status = AuthStatus.authenticated;
          notifyListeners();
        } else {
          _status = AuthStatus.unauthenticated;
          notifyListeners();
        }
      } else {
        _status = AuthStatus.unauthenticated;
        notifyListeners();
      }
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
      await _apiService.logout();
    } catch (e) {
      // Continue with logout even if API call fails
    }

    _user = null;
    _status = AuthStatus.unauthenticated;
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
