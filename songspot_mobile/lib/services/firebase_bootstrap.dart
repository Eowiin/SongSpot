import 'package:firebase_core/firebase_core.dart';

/// Single entry point for Firebase initialization.
///
/// Firebase used to be initialized only from [PushNotificationService], which
/// meant anything else built on Firebase silently depended on push setup
/// having succeeded first — a user who declined notifications, or a failure in
/// that service, took the rest down with it. Every caller now goes through
/// here instead.
class FirebaseBootstrap {
  FirebaseBootstrap._();

  static Future<void>? _pending;

  /// Idempotent, and safe to call concurrently: callers share one
  /// initialization. A failed attempt is not cached, so a later call retries.
  static Future<void> ensureInitialized() {
    final pending = _pending;
    if (pending != null) return pending;

    final started = _initialize();
    _pending = started;
    return started.catchError((Object error) {
      _pending = null;
      throw error;
    });
  }

  static Future<void> _initialize() async {
    // Already initialized (background isolate, hot restart): calling
    // initializeApp() again would throw a duplicate-app error.
    if (Firebase.apps.isNotEmpty) return;
    await Firebase.initializeApp();
  }
}
