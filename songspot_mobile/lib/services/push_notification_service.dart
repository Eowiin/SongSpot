import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'firebase_bootstrap.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await FirebaseBootstrap.ensureInitialized();
  } catch (_) {
    // Firebase may already be initialized in the background isolate.
  }
}

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService _instance = PushNotificationService._();
  factory PushNotificationService() => _instance;

  final ApiService _apiService = ApiService();
  FirebaseMessaging? _messaging;

  bool _initialized = false;
  StreamSubscription<String>? _tokenRefreshSubscription;

  void Function(Map<String, dynamic> data)? _onNotificationTap;

  /// Register a callback invoked when the user taps a push notification.
  void setOnNotificationTap(void Function(Map<String, dynamic> data) callback) {
    _onNotificationTap = callback;
  }

  Future<void> initializeCore() async {
    if (_initialized) return;

    // Web push needs a service worker, a VAPID key and per-origin FCM
    // credentials that the mobile config does not carry. The web build plays
    // fine without notifications, so skip the whole stack there.
    if (kIsWeb) {
      debugPrint('Push notifications are not enabled on web');
      return;
    }

    try {
      await FirebaseBootstrap.ensureInitialized();
    } catch (e) {
      debugPrint('Firebase initialization skipped: $e');
      return;
    }

    _messaging = FirebaseMessaging.instance;
    final messaging = _messaging;
    if (messaging == null) return;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await messaging.setAutoInitEnabled(true);
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = messaging.onTokenRefresh.listen((token) async {
      await _registerToken(token);
    });

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Handle notification tap that launched the app from terminated state
    messaging.getInitialMessage().then((message) {
      if (message != null) {
        _handleNotificationTap(message);
      }
    });

    _initialized = true;
  }

  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    if (data.isNotEmpty && _onNotificationTap != null) {
      _onNotificationTap!(Map<String, dynamic>.from(data));
    }
  }

  Future<void> syncTokenWithBackend() async {
    await initializeCore();
    if (!_initialized) return;
    final messaging = _messaging;
    if (messaging == null) return;

    final permission = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (permission.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }

    final token = await messaging.getToken();
    if (token == null || token.isEmpty) return;

    await _registerToken(token);
  }

  Future<void> unregisterCurrentToken() async {
    await initializeCore();
    if (!_initialized) return;
    final messaging = _messaging;
    if (messaging == null) return;

    final token = await messaging.getToken();
    if (token == null || token.isEmpty) return;

    try {
      await _apiService.unregisterPushDevice(token: token);
    } catch (e) {
      debugPrint('FCM token unregister failed: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await _apiService.registerPushDevice(
        token: token,
        platform: _platformName,
      );
    } catch (e) {
      debugPrint('FCM token register failed: $e');
    }
  }

  String get _platformName {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'ios';
    }
    return 'android';
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }
}
