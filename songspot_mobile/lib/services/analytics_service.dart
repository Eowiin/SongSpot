import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_bootstrap.dart';

/// Product analytics on top of Firebase Analytics (GA4).
///
/// Event names and parameters are declared here and nowhere else: they are the
/// expensive thing to change later, because renaming one splits its history in
/// GA4. Anything the backend can already answer from `GameScore` is
/// deliberately absent — this covers what the server cannot see (guests,
/// people who open the app without playing, sessions abandoned mid-run).
///
/// DAU/MAU and retention are not instrumented: GA4 derives them from its own
/// automatic `session_start` — which is also why the run events below are
/// named `game_run_*`, since `session_start` is reserved and rejected if
/// logged manually.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService _instance = AnalyticsService._();
  factory AnalyticsService() => _instance;

  /// Shared with SettingsProvider so the toggle and this service cannot
  /// drift apart on the stored value.
  static const prefsKeyEnabled = 'settings_analytics_enabled';

  /// Opt-out rather than opt-in. Revisit for EU users: collection without a
  /// prior prompt is the part a CNIL/GDPR review would question. Flipping this
  /// to `false` makes the app opt-in with no other code change.
  /// Opt-in: collection stays off until the user turns it on. Required by
  /// ePrivacy art. 5(3) (FR/IT/DE transpositions) for our EU-majority
  /// audience — Firebase Analytics writes an app-instance id to the device
  /// and is not strictly necessary to the service.
  static const bool defaultEnabled = false;

  FirebaseAnalytics? _analytics;
  bool _enabled = defaultEnabled;
  bool _initialized = false;

  bool get isEnabled => _enabled;

  /// The singleton would otherwise carry state between tests, making the
  /// consent assertions depend on declaration order.
  @visibleForTesting
  void resetForTest() {
    _analytics = null;
    _enabled = defaultEnabled;
    _initialized = false;
  }

  /// Never throws: analytics must not be able to block app start-up.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(prefsKeyEnabled) ?? defaultEnabled;

      await FirebaseBootstrap.ensureInitialized();
      final analytics = FirebaseAnalytics.instance;
      await analytics.setAnalyticsCollectionEnabled(_enabled);
      _analytics = analytics;
      _initialized = true;
    } catch (e) {
      debugPrint('[Analytics] initialize failed: $e');
    }
  }

  /// Wired to the settings toggle. Takes effect immediately and persists.
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKeyEnabled, value);
      await _analytics?.setAnalyticsCollectionEnabled(value);
    } catch (e) {
      debugPrint('[Analytics] setEnabled failed: $e');
    }
  }

  // ── Events ────────────────────────────────────────────────────────────────

  /// A run begins. `genre` and `artist` are mutually exclusive.
  Future<void> sessionStarted({
    required String mode,
    String? genre,
    String? artist,
    required String difficulty,
  }) {
    return _log('game_run_start', {
      'mode': mode,
      'genre': genre ?? '',
      'artist': artist ?? '',
      'difficulty': difficulty,
    });
  }

  /// A run ends, whether finished, failed or abandoned. `endReason` is what
  /// separates "played to the end" from "walked away".
  Future<void> sessionEnded({
    required String mode,
    required int songsPlayed,
    required int songsCorrect,
    required int bestStreak,
    required int score,
    required String endReason,
  }) {
    return _log('game_run_end', {
      'mode': mode,
      'songs_played': songsPlayed,
      'songs_correct': songsCorrect,
      'best_streak': bestStreak,
      'score': score,
      'end_reason': endReason,
    });
  }

  /// `replayCount` > 0 means the player needed to hear the snippet again —
  /// the signal for whether a difficulty is tuned right.
  Future<void> snippetPlayed({
    required String difficulty,
    required int replayCount,
  }) {
    return _log('snippet_play', {
      'difficulty': difficulty,
      'replay_count': replayCount,
    });
  }

  /// `songIndex` is the position in the run (1-based), which is what shows
  /// where in a run players start getting it wrong.
  Future<void> guessSubmitted({
    required bool correct,
    required bool gaveUp,
    required int songIndex,
    required String difficulty,
  }) {
    return _log('guess_submitted', {
      'correct': correct ? 1 : 0,
      'gave_up': gaveUp ? 1 : 0,
      'song_index': songIndex,
      'difficulty': difficulty,
    });
  }

  /// The product-side counterpart to the Sentry audio crash: Sentry reports
  /// that something threw, this reports how often players actually lose audio
  /// and whether the URL refresh rescued them.
  Future<void> audioLoadFailed({required bool retrySucceeded}) {
    return _log('audio_load_failed', {
      'retry_succeeded': retrySucceeded ? 1 : 0,
    });
  }

  Future<void> duelMatched() => _log('duel_matched', const {});


  Future<void> duelFinished({
    required String result,
    required int eloChange,
  }) {
    return _log('duel_finished', {
      'result': result,
      'elo_change': eloChange,
    });
  }

  Future<void> signupCompleted({required bool fromGuest}) {
    return _log('signup_completed', {'from_guest': fromGuest ? 1 : 0});
  }

  // ── Plumbing ──────────────────────────────────────────────────────────────

  /// Analytics failures are swallowed on purpose: a telemetry problem must
  /// never surface as a broken game.
  Future<void> _log(String name, Map<String, Object> parameters) async {
    final analytics = _analytics;
    if (analytics == null || !_enabled) return;
    try {
      await analytics.logEvent(
        name: name,
        // An empty map is rejected; the SDK wants null for a bare event.
        parameters: parameters.isEmpty ? null : parameters,
      );
    } catch (e) {
      debugPrint('[Analytics] $name failed: $e');
    }
  }
}
