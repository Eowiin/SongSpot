import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
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

  Future<void> initializeCore() async {
    if (_initialized) return;

    try {
      await Firebase.initializeApp();
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

    _initialized = true;
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
