import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/models/message.dart';
import 'package:songspot_mobile/providers/game_provider.dart';
import 'package:songspot_mobile/services/api_service.dart';
import 'package:songspot_mobile/services/audio_service.dart';
import 'package:songspot_mobile/services/websocket_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const roomId = 'room-1';
  const mixMode = 'mix';
  const genreMode = 'genre';
  const activeGameDate = '2026-03-16';

  late FakeApiService apiService;
  late FakeAudioService audioService;
  late FakeWebSocketService webSocketService;
  late GameProvider provider;

  setUp(() {
    apiService = FakeApiService();
    audioService = FakeAudioService();
    webSocketService = FakeWebSocketService();
    provider = GameProvider(
      apiService: apiService,
      audioService: audioService,
      webSocketService: webSocketService,
      nowProvider: fixedNow,
    );
  });

  tearDown(() async {
    provider.dispose();
  });

  test(
    'restoreCachedModeState hydrates cached session state for a room and mode',
    () async {
      apiService.startSessionResponses[mixMode] = _sessionJson(
        sessionId: 'session-mix',
        mode: mixMode,
        date: activeGameDate,
        currentSnippet: 2,
      );
      apiService.leaderboardResponses[mixMode] = [
        _leaderboardEntryJson(username: 'alice', pointsEarned: 5),
      ];
      apiService.messagesResponses[mixMode] = [
        _messageJson(id: 'message-1', text: 'cached hello'),
      ];

      await provider.startGameSession(roomId, mode: mixMode);
      await provider.loadLeaderboard(roomId, mode: mixMode);
      await provider.loadMessages(roomId, mode: mixMode);

      apiService.startSessionResponses[genreMode] = _sessionJson(
        sessionId: 'session-genre',
        mode: genreMode,
        date: activeGameDate,
        currentSnippet: 4,
        genreName: 'Rock',
      );
      await provider.startGameSession(roomId, mode: genreMode);

      final restored = provider.restoreCachedModeState(roomId, mode: mixMode);

      expect(restored, isTrue);
      expect(provider.currentMode, mixMode);
      expect(provider.currentSession?.id, 'session-mix');
      expect(provider.currentSession?.currentSnippet, 2);
      expect(provider.leaderboard.single.user.username, 'alice');
      expect(provider.messages.single.message, 'cached hello');
    },
  );

  test(
    'restoreCachedModeState rejects snapshots for an inactive daily date',
    () async {
      apiService.startSessionResponses[mixMode] = _sessionJson(
        sessionId: 'session-stale',
        mode: mixMode,
        date: '2026-03-15',
      );

      await provider.startGameSession(roomId, mode: mixMode);

      final restored = provider.restoreCachedModeState(roomId, mode: mixMode);

      expect(restored, isFalse);
      expect(provider.debugCachedModeState(roomId, mode: mixMode), isNull);
    },
  );

  test(
    'mutations and realtime messages update the active mode cache',
    () async {
      apiService.startSessionResponses[mixMode] = _sessionJson(
        sessionId: 'session-mix',
        mode: mixMode,
        date: activeGameDate,
        currentSnippet: 1,
      );
      apiService.leaderboardResponses[mixMode] = [
        _leaderboardEntryJson(username: 'alice', pointsEarned: 6),
      ];
      apiService.messagesResponses[mixMode] = [
        _messageJson(id: 'message-1', text: 'server message'),
      ];
      apiService.skipResponse = {'current_snippet': 2};
      apiService.submitGuessResponse = {
        'is_correct': false,
        'message': 'Nope',
        'current_snippet': 3,
        'retries_used': 0,
        'retry_credits': 0,
        'awaiting_retry_unlock': false,
        'retry_available': false,
        'retry_cost_coins': 10,
        'next_retry_requirement': null,
        'game_over': false,
        'guess_counted': true,
        'points_earned': 0,
      };
      apiService.retryResponse = {
        'message': 'Retry unlocked',
        'retry_credits': 1,
        'retries_used': 1,
        'awaiting_retry_unlock': false,
        'retry_available': true,
        'next_retry_requirement': null,
        'retry_cost_coins': 10,
        'game_over': false,
      };
      apiService.hintResponses['$mixMode:title'] = {
        'hint_value': 'Test Song',
        'coins': 10,
      };

      await provider.startGameSession(roomId, mode: mixMode);
      await provider.loadLeaderboard(roomId, mode: mixMode);
      await provider.loadMessages(roomId, mode: mixMode);
      await provider.connectToChat(roomId, mode: mixMode);

      await provider.skipSnippet(roomId, mode: mixMode);
      expect(
        provider
            .debugCachedModeState(roomId, mode: mixMode)
            ?.session
            ?.currentSnippet,
        2,
      );

      await provider.submitGuess(
        roomId: roomId,
        trackId: 'track-1',
        mode: mixMode,
      );
      expect(
        provider
            .debugCachedModeState(roomId, mode: mixMode)
            ?.session
            ?.guessesMade,
        1,
      );

      await provider.activateRetry(
        roomId: roomId,
        action: 'unlock',
        mode: mixMode,
      );
      expect(
        provider
            .debugCachedModeState(roomId, mode: mixMode)
            ?.session
            ?.retryCredits,
        1,
      );

      await provider.purchaseHint(
        roomId: roomId,
        hintType: 'title',
        mode: mixMode,
      );
      expect(
        provider
            .debugCachedModeState(roomId, mode: mixMode)
            ?.hintValues['title'],
        'Test Song',
      );

      webSocketService.emit(
        WebSocketEvent(
          WebSocketEventType.message,
          Message.fromJson(
            _messageJson(id: 'message-2', text: 'realtime hello'),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        provider
            .debugCachedModeState(roomId, mode: mixMode)
            ?.messages
            .first
            .message,
        'realtime hello',
      );
    },
  );

  test('skipSnippet stops active playback before advancing', () async {
    apiService.startSessionResponses[mixMode] = _sessionJson(
      sessionId: 'session-mix',
      mode: mixMode,
      date: activeGameDate,
      currentSnippet: 2,
    );
    apiService.skipResponse = {'current_snippet': 3};

    await provider.startGameSession(roomId, mode: mixMode);
    await provider.skipSnippet(roomId, mode: mixMode);

    expect(audioService.stopCallCount, 1);
    expect(provider.currentSession?.currentSnippet, 3);
  });

  test('startGameSession does not wait for audio preload to finish', () async {
    apiService.startSessionResponses[mixMode] = _sessionJson(
      sessionId: 'session-mix',
      mode: mixMode,
      date: activeGameDate,
      currentSnippet: 1,
    );
    audioService.pendingLoad = Completer<void>();

    await provider
        .startGameSession(roomId, mode: mixMode)
        .timeout(const Duration(milliseconds: 100));

    expect(provider.currentSession?.id, 'session-mix');
    expect(audioService.lastLoadedUrl, 'https://example.com/preview.mp3');

    audioService.pendingLoad?.complete();
  });

  test(
    'startGameSession(clearVisibleState: false) keeps the current session visible',
    () async {
      apiService.startSessionResponses[mixMode] = _sessionJson(
        sessionId: 'session-old',
        mode: mixMode,
        date: activeGameDate,
        currentSnippet: 2,
      );
      await provider.startGameSession(roomId, mode: mixMode);

      final completer = Completer<Map<String, dynamic>>();
      apiService.startSessionCompleters[mixMode] = completer;

      final future = provider.startGameSession(
        roomId,
        mode: mixMode,
        clearVisibleState: false,
      );

      expect(provider.currentSession?.id, 'session-old');
      expect(provider.currentSession?.currentSnippet, 2);

      completer.complete(
        _sessionJson(
          sessionId: 'session-new',
          mode: mixMode,
          date: activeGameDate,
          currentSnippet: 5,
        ),
      );
      await future;

      expect(provider.currentSession?.id, 'session-new');
      expect(provider.currentSession?.currentSnippet, 5);
    },
  );
}

DateTime fixedNow() => DateTime.utc(2026, 3, 16, 13);

class FakeApiService extends ApiService {
  final Map<String, Map<String, dynamic>> startSessionResponses = {};
  final Map<String, Completer<Map<String, dynamic>>> startSessionCompleters =
      {};
  final Map<String, List<Map<String, dynamic>>> leaderboardResponses = {};
  final Map<String, List<Map<String, dynamic>>> messagesResponses = {};
  final Map<String, Map<String, dynamic>> hintResponses = {};
  Map<String, dynamic> skipResponse = const {'current_snippet': 1};
  Map<String, dynamic> submitGuessResponse = const {
    'is_correct': false,
    'message': 'Nope',
    'current_snippet': 1,
    'retries_used': 0,
    'retry_credits': 0,
    'awaiting_retry_unlock': false,
    'retry_available': false,
    'retry_cost_coins': 10,
    'next_retry_requirement': null,
    'game_over': false,
    'guess_counted': true,
    'points_earned': 0,
  };
  Map<String, dynamic> retryResponse = const {
    'message': 'Retry unlocked',
    'retry_credits': 1,
    'retries_used': 1,
    'awaiting_retry_unlock': false,
    'retry_available': true,
    'next_retry_requirement': null,
    'retry_cost_coins': 10,
    'game_over': false,
  };

  @override
  Future<Map<String, dynamic>> startGameSession(
    String roomId, {
    String mode = 'mix',
  }) async {
    final completer = startSessionCompleters.remove(mode);
    if (completer != null) {
      return completer.future;
    }
    return startSessionResponses[mode]!;
  }

  @override
  Future<Map<String, dynamic>> purchaseDailyGameHint({
    required String roomId,
    required String hintType,
    String mode = 'mix',
  }) async {
    return hintResponses['$mode:$hintType']!;
  }

  @override
  Future<Map<String, dynamic>> getLeaderboard(
    String roomId, {
    String mode = 'mix',
  }) async {
    return {'leaderboard': leaderboardResponses[mode] ?? const []};
  }

  @override
  Future<Map<String, dynamic>> getMessages({
    required String roomId,
    String mode = 'mix',
    int limit = 50,
    int offset = 0,
  }) async {
    return {'messages': messagesResponses[mode] ?? const []};
  }

  @override
  Future<Map<String, dynamic>> skipSnippet(
    String roomId, {
    String mode = 'mix',
  }) async {
    return skipResponse;
  }

  @override
  Future<Map<String, dynamic>> submitGuess({
    required String roomId,
    required String trackId,
    String mode = 'mix',
  }) async {
    return submitGuessResponse;
  }

  @override
  Future<Map<String, dynamic>> activateDailyRetry({
    required String roomId,
    required String action,
    String mode = 'mix',
  }) async {
    return retryResponse;
  }
}

class FakeAudioService extends AudioService {
  String? lastLoadedUrl;
  Completer<void>? pendingLoad;
  int stopCallCount = 0;

  @override
  Future<void> loadAudio(String url) async {
    lastLoadedUrl = url;
    final completer = pendingLoad;
    if (completer != null) {
      await completer.future;
    }
  }

  @override
  Future<void> stop({bool cancelTimer = true}) async {
    stopCallCount += 1;
  }

  @override
  Future<void> dispose() async {}
}

class FakeWebSocketService extends WebSocketService {
  final StreamController<WebSocketEvent> _controller =
      StreamController<WebSocketEvent>.broadcast();

  @override
  Stream<WebSocketEvent> get events => _controller.stream;

  @override
  Future<bool> connect(String roomId, {String mode = 'mix'}) async {
    _controller.add(WebSocketEvent(WebSocketEventType.connected));
    return true;
  }

  @override
  Future<void> disconnect() async {
    _controller.add(WebSocketEvent(WebSocketEventType.disconnected));
  }

  @override
  bool sendMessage(String message, {String? clientMessageId}) => true;

  void emit(WebSocketEvent event) {
    _controller.add(event);
  }

  @override
  void dispose() {
    _controller.close();
  }
}

Map<String, dynamic> _sessionJson({
  required String sessionId,
  required String mode,
  required String date,
  int currentSnippet = 1,
  String? genreName,
}) {
  return {
    'id': sessionId,
    'user': _userJson('player-1', 'player1'),
    'daily_song': {
      'id': 'daily-$mode',
      'track': {
        'id': 'track-1',
        'title': 'Test Song',
        'artist': 'Test Artist',
        'preview_url': 'https://example.com/preview.mp3',
        'cover_url': null,
        'created_at': '2026-03-16T12:00:00Z',
      },
      'mode': mode,
      'genre_key': genreName == null ? null : 'rock',
      'genre_name': genreName,
      'date': date,
      'created_at': '2026-03-16T12:00:00Z',
    },
    'current_snippet': currentSnippet,
    'guesses_made': 0,
    'retries_used': 0,
    'retry_credits': 0,
    'awaiting_retry_unlock': false,
    'retry_available': false,
    'retry_cost_coins': 10,
    'correct_guess': false,
    'points_earned': null,
    'completed_at': null,
    'created_at': '2026-03-16T12:00:00Z',
    'hints_used': <String>[],
  };
}

Map<String, dynamic> _leaderboardEntryJson({
  required String username,
  required int pointsEarned,
}) {
  return {
    'user': _userJson('user-$username', username),
    'points_earned': pointsEarned,
    'snippet_number': 2,
    'completed_at': '2026-03-16T12:05:00Z',
  };
}

Map<String, dynamic> _messageJson({required String id, required String text}) {
  return {
    'id': id,
    'user': _userJson('chat-user', 'chatuser'),
    'message': text,
    'created_at': '2026-03-16T12:10:00Z',
  };
}

Map<String, dynamic> _userJson(String id, String username) {
  return {'id': id, 'email': '$username@example.com', 'username': username};
}
