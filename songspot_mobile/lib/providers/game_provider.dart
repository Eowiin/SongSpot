import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/game_session.dart';
import '../models/message.dart';
import '../models/track.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/websocket_service.dart';

class GameProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final AudioService _audioService = AudioService();
  final WebSocketService _webSocketService = WebSocketService();

  StreamSubscription<WebSocketEvent>? _wsSubscription;

  GameSession? _currentSession;
  List<LeaderboardEntry> _leaderboard = [];
  List<Message> _messages = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _guessResult;
  bool _isWebSocketConnected = false;
  String? _currentChatRoomId;
  Map<String, bool> _typingUsers = {}; // userId -> isTyping
  Map<String, String> _hintValues = {}; // hintType -> revealed value

  GameSession? get currentSession => _currentSession;
  List<LeaderboardEntry> get leaderboard => _leaderboard;
  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get guessResult => _guessResult;
  AudioService get audioService => _audioService;
  bool get isWebSocketConnected => _isWebSocketConnected;
  Map<String, String> get hintValues => _hintValues;
  Stream<WebSocketEvent> get webSocketEvents => _webSocketService.events;
  List<String> get typingUsernames =>
      _typingUsers.entries.where((e) => e.value).map((e) => e.key).toList();

  /// Start or get current game session
  Future<void> startGameSession(String roomId) async {
    try {
      // Clear previous session immediately to avoid showing stale data
      _currentSession = null;
      _leaderboard = [];
      _messages = [];
      _hintValues = {};
      _isLoading = true;
      _errorMessage = null;
      _guessResult = null;
      notifyListeners();

      final response = await _apiService.startGameSession(roomId);
      _currentSession = GameSession.fromJson(response);

      // Restore any already-purchased hints (re-fetch values without charging)
      for (final hintType in _currentSession!.hintsUsed) {
        try {
          final hintResponse = await _apiService.purchaseDailyGameHint(
            roomId: roomId,
            hintType: hintType,
          );
          _hintValues[hintType] = hintResponse['hint_value'] as String;
        } catch (_) {
          // Non-fatal — hint button will remain purchasable but won't double-charge
        }
      }

      // Load the audio
      await _loadAudioWithRefresh(_currentSession!);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load game: $e';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _loadAudioWithRefresh(GameSession session) async {
    final previewUrl = session.dailySong.track.previewUrl;
    if (previewUrl.isNotEmpty) {
      try {
        await _audioService.loadAudio(previewUrl);
        return;
      } catch (e) {
        // Fall through to refresh.
      }
    }

    final refreshed = await _apiService.refreshTrackPreview(
      trackId: session.dailySong.track.id,
    );
    final trackJson = refreshed['track'] as Map<String, dynamic>;
    final updatedTrack = Track.fromJson(trackJson);
    _currentSession = _copySessionWithTrack(session, updatedTrack);
    await _audioService.loadAudio(updatedTrack.previewUrl);
  }

  GameSession _copySessionWithTrack(GameSession session, Track updatedTrack) {
    final updatedDailySong = DailySong(
      id: session.dailySong.id,
      track: updatedTrack,
      date: session.dailySong.date,
      createdAt: session.dailySong.createdAt,
    );

    return session.copyWith(dailySong: updatedDailySong);
  }

  /// Skip to next snippet
  Future<void> skipSnippet(String roomId) async {
    if (_currentSession == null) return;

    try {
      _isLoading = true;
      _errorMessage = null;
      _guessResult = null;
      notifyListeners();

      final response = await _apiService.skipSnippet(roomId);

      // Update current snippet
      final newSnippet = response['current_snippet'] as int;
      _currentSession = _currentSession!.copyWith(currentSnippet: newSnippet);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Submit a guess
  Future<Map<String, dynamic>?> submitGuess({
    required String roomId,
    required String trackId,
  }) async {
    if (_currentSession == null) return null;

    try {
      _isLoading = true;
      _errorMessage = null;
      _guessResult = null;
      notifyListeners();

      final response = await _apiService.submitGuess(
        roomId: roomId,
        trackId: trackId,
      );

      final isCorrect = response['is_correct'] as bool;
      _guessResult = response['message'] as String;
      final current = _currentSession!;
      final nextSnippet =
          response['current_snippet'] as int? ?? current.currentSnippet;
      final retriesUsed =
          response['retries_used'] as int? ?? current.retriesUsed;
      final retryCredits =
          response['retry_credits'] as int? ?? current.retryCredits;
      final awaitingRetryUnlock =
          response['awaiting_retry_unlock'] as bool? ??
          current.awaitingRetryUnlock;
      final retryAvailable =
          response['retry_available'] as bool? ?? current.retryAvailable;
      final retryCostCoins =
          response['retry_cost_coins'] as int? ?? current.retryCostCoins;
      final gameOver = response['game_over'] as bool? ?? false;
      final guessCounted = response['guess_counted'] as bool? ?? true;
      final nextGuessesMade = current.guessesMade + (guessCounted ? 1 : 0);

      if (isCorrect) {
        _currentSession = current.copyWith(
          guessesMade: nextGuessesMade,
          correctGuess: true,
          pointsEarned: response['points_earned'] as int?,
          completedAt: DateTime.now(),
          retriesUsed: retriesUsed,
          retryCredits: retryCredits,
          awaitingRetryUnlock: awaitingRetryUnlock,
          retryAvailable: retryAvailable,
          nextRetryRequirement: response['next_retry_requirement'] as String?,
          clearNextRetryRequirement: response['next_retry_requirement'] == null,
          retryCostCoins: retryCostCoins,
        );
      } else {
        _currentSession = current.copyWith(
          currentSnippet: nextSnippet,
          guessesMade: nextGuessesMade,
          correctGuess: false,
          pointsEarned:
              response['points_earned'] as int? ?? current.pointsEarned,
          completedAt: gameOver ? DateTime.now() : null,
          clearCompletedAt: !gameOver,
          retriesUsed: retriesUsed,
          retryCredits: retryCredits,
          awaitingRetryUnlock: awaitingRetryUnlock,
          retryAvailable: retryAvailable,
          nextRetryRequirement: response['next_retry_requirement'] as String?,
          clearNextRetryRequirement: response['next_retry_requirement'] == null,
          retryCostCoins: retryCostCoins,
        );
      }

      _isLoading = false;
      notifyListeners();
      return response;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Activate a retry after failing on the last snippet.
  Future<Map<String, dynamic>?> activateRetry({
    required String roomId,
    required String action,
  }) async {
    if (_currentSession == null) return null;

    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response = await _apiService.activateDailyRetry(
        roomId: roomId,
        action: action,
      );

      final current = _currentSession!;
      final gameOver = response['game_over'] as bool? ?? false;
      _currentSession = current.copyWith(
        retryCredits: response['retry_credits'] as int? ?? current.retryCredits,
        retriesUsed: response['retries_used'] as int? ?? current.retriesUsed,
        awaitingRetryUnlock:
            response['awaiting_retry_unlock'] as bool? ??
            current.awaitingRetryUnlock,
        retryAvailable:
            response['retry_available'] as bool? ?? current.retryAvailable,
        nextRetryRequirement: response['next_retry_requirement'] as String?,
        clearNextRetryRequirement: response['next_retry_requirement'] == null,
        retryCostCoins:
            response['retry_cost_coins'] as int? ?? current.retryCostCoins,
        correctGuess: gameOver
            ? (response['is_correct'] as bool? ?? false)
            : current.correctGuess,
        pointsEarned: gameOver
            ? (response['points_earned'] as int? ?? 0)
            : current.pointsEarned,
        completedAt: gameOver ? DateTime.now() : current.completedAt,
      );

      _guessResult = response['message'] as String?;
      _isLoading = false;
      notifyListeners();
      return response;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Purchase a hint for the current game session.
  /// Returns a map with `hint_value` (String) and `coins` (int, new balance).
  /// Throws on API error (e.g. insufficient coins).
  Future<Map<String, dynamic>> purchaseHint({
    required String roomId,
    required String hintType,
  }) async {
    final response = await _apiService.purchaseDailyGameHint(
      roomId: roomId,
      hintType: hintType,
    );

    final hintValue = response['hint_value'] as String;
    _hintValues[hintType] = hintValue;

    // Update hintsUsed on the session if not already present
    if (_currentSession != null &&
        !_currentSession!.hintsUsed.contains(hintType)) {
      final updatedHints = List<String>.from(_currentSession!.hintsUsed)
        ..add(hintType);
      _currentSession = _currentSession!.copyWith(hintsUsed: updatedHints);
    }

    notifyListeners();
    return response;
  }

  /// Load leaderboard
  Future<void> loadLeaderboard(String roomId, {bool silent = false}) async {
    try {
      if (!silent) {
        _isLoading = true;
        _errorMessage = null;
        notifyListeners();
      }

      final response = await _apiService.getLeaderboard(roomId);
      _leaderboard = (response['leaderboard'] as List)
          .map(
            (entry) => LeaderboardEntry.fromJson(entry as Map<String, dynamic>),
          )
          .toList();

      if (!silent) {
        _isLoading = false;
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      if (!silent) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  /// Connect to room chat WebSocket
  Future<void> connectToChat(String roomId) async {
    // Cancel any existing subscription
    await _wsSubscription?.cancel();

    // Subscribe to WebSocket events
    _wsSubscription = _webSocketService.events.listen(_handleWebSocketEvent);

    // Connect to the room
    final connected = await _webSocketService.connect(roomId);
    _isWebSocketConnected = connected;
    _currentChatRoomId = roomId;
    notifyListeners();
  }

  /// Disconnect from chat WebSocket
  Future<void> disconnectFromChat() async {
    await _wsSubscription?.cancel();
    _wsSubscription = null;
    await _webSocketService.disconnect();
    _isWebSocketConnected = false;
    _currentChatRoomId = null;
    _typingUsers.clear();
    notifyListeners();
  }

  void _handleWebSocketEvent(WebSocketEvent event) {
    switch (event.type) {
      case WebSocketEventType.connected:
        _isWebSocketConnected = true;
        notifyListeners();
        break;

      case WebSocketEventType.disconnected:
        _isWebSocketConnected = false;
        notifyListeners();
        break;

      case WebSocketEventType.message:
        final message = event.data as Message;
        // Add to beginning (newest first), avoid duplicates
        if (!_messages.any((m) => m.id == message.id)) {
          _messages.insert(0, message);
          notifyListeners();
        }
        break;

      case WebSocketEventType.leaderboardUpdated:
        final roomId = _currentChatRoomId;
        if (roomId != null) {
          unawaited(loadLeaderboard(roomId, silent: true));
        }
        break;

      case WebSocketEventType.userJoined:
        // Could show a notification or update UI
        debugPrint('User joined: ${(event.data as User).username}');
        notifyListeners();
        break;

      case WebSocketEventType.userLeft:
        final user = event.data as User;
        _typingUsers.remove(user.id);
        debugPrint('User left: ${user.username}');
        notifyListeners();
        break;

      case WebSocketEventType.typing:
        final data = event.data as Map<String, dynamic>;
        final user = data['user'] as User;
        final isTyping = data['is_typing'] as bool;
        if (isTyping) {
          _typingUsers[user.username] = true;
        } else {
          _typingUsers.remove(user.username);
        }
        notifyListeners();
        break;

      case WebSocketEventType.stemsReady:
        // Handled by PackBundleContent via webSocketEvents stream
        break;

      case WebSocketEventType.error:
        _errorMessage = event.data?.toString();
        notifyListeners();
        break;
    }
  }

  /// Load messages (initial load via REST API)
  Future<void> loadMessages(
    String roomId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await _apiService.getMessages(
        roomId: roomId,
        limit: limit,
        offset: offset,
      );

      _messages = (response['messages'] as List)
          .map((msg) => Message.fromJson(msg as Map<String, dynamic>))
          .toList();

      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Send a message via WebSocket (real-time) or REST API (fallback)
  Future<bool> sendMessage(String roomId, String message) async {
    // Try WebSocket first for real-time delivery
    if (_isWebSocketConnected) {
      final sent = _webSocketService.sendMessage(message);
      if (sent) {
        return true;
      }
    }

    // Fallback to REST API
    try {
      final response = await _apiService.sendMessage(
        roomId: roomId,
        message: message,
      );

      final newMessage = Message.fromJson(response);
      _messages.insert(0, newMessage); // Add to beginning (newest first)

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Send typing indicator
  void sendTypingIndicator(bool isTyping) {
    if (_isWebSocketConnected) {
      _webSocketService.sendTyping(isTyping);
    }
  }

  /// Play current snippet
  Future<void> playCurrentSnippet() async {
    if (_currentSession != null) {
      try {
        // Notify UI that playback is starting
        notifyListeners();

        await _audioService.playSnippetByNumber(
          _currentSession!.currentSnippet,
        );

        // Notify UI that playback has finished
        notifyListeners();
      } catch (e) {
        _errorMessage = 'Failed to play audio: $e';
        notifyListeners();
        rethrow;
      }
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear guess result
  void clearGuessResult() {
    _guessResult = null;
    notifyListeners();
  }

  /// Reset game state
  void reset() {
    _currentSession = null;
    _leaderboard = [];
    _messages = [];
    _errorMessage = null;
    _guessResult = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _webSocketService.dispose();
    _audioService.dispose();
    super.dispose();
  }
}
