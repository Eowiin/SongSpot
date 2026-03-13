import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
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
  final Uuid _uuid = const Uuid();
  final Map<String, Timer> _pendingMessageTimeouts = {};
  static const Duration _pendingMessageTimeout = Duration(seconds: 15);

  StreamSubscription<WebSocketEvent>? _wsSubscription;

  GameSession? _currentSession;
  List<LeaderboardEntry> _leaderboard = [];
  List<Message> _messages = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _guessResult;
  bool _isWebSocketConnected = false;
  String? _currentChatRoomId;
  final Map<String, bool> _typingUsers = {}; // userId -> isTyping
  Map<String, String> _hintValues = {}; // hintType -> revealed value
  int _playSnippetRequestId = 0;
  String _currentMode = 'mix';

  GameSession? get currentSession => _currentSession;
  List<LeaderboardEntry> get leaderboard => _leaderboard;
  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get guessResult => _guessResult;
  AudioService get audioService => _audioService;
  bool get isWebSocketConnected => _isWebSocketConnected;
  Map<String, String> get hintValues => _hintValues;
  String get currentMode => _currentMode;
  Stream<WebSocketEvent> get webSocketEvents => _webSocketService.events;
  List<String> get typingUsernames =>
      _typingUsers.entries.where((e) => e.value).map((e) => e.key).toList();

  /// Start or get current game session
  Future<void> startGameSession(String roomId, {String mode = 'mix'}) async {
    try {
      _currentMode = mode;
      // Clear previous session immediately to avoid showing stale data
      _currentSession = null;
      _leaderboard = [];
      _messages = [];
      _clearPendingMessageTimeouts();
      _hintValues = {};
      _isLoading = true;
      _errorMessage = null;
      _guessResult = null;
      notifyListeners();

      final response = await _apiService.startGameSession(roomId, mode: mode);
      _currentSession = GameSession.fromJson(response);

      // Restore any already-purchased hints (re-fetch values without charging)
      for (final hintType in _currentSession!.hintsUsed) {
        try {
          final hintResponse = await _apiService.purchaseDailyGameHint(
            roomId: roomId,
            hintType: hintType,
            mode: mode,
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

    await _refreshAndLoadAudio(session);
  }

  Future<GameSession> _refreshAndLoadAudio(GameSession session) async {
    final refreshed = await _apiService.refreshTrackPreview(
      trackId: session.dailySong.track.id,
    );
    final trackJson = refreshed['track'] as Map<String, dynamic>;
    final updatedTrack = Track.fromJson(trackJson);
    final updatedSession = _copySessionWithTrack(session, updatedTrack);
    _currentSession = updatedSession;
    await _audioService.loadAudio(updatedTrack.previewUrl);
    return updatedSession;
  }

  GameSession _copySessionWithTrack(GameSession session, Track updatedTrack) {
    final updatedDailySong = DailySong(
      id: session.dailySong.id,
      track: updatedTrack,
      mode: session.dailySong.mode,
      genreKey: session.dailySong.genreKey,
      genreName: session.dailySong.genreName,
      date: session.dailySong.date,
      createdAt: session.dailySong.createdAt,
    );

    return session.copyWith(dailySong: updatedDailySong);
  }

  /// Skip to next snippet
  Future<void> skipSnippet(String roomId, {String? mode}) async {
    if (_currentSession == null) return;

    try {
      _isLoading = true;
      _errorMessage = null;
      _guessResult = null;
      notifyListeners();

      final response = await _apiService.skipSnippet(
        roomId,
        mode: mode ?? _currentMode,
      );

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
    String? mode,
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
        mode: mode ?? _currentMode,
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
    String? mode,
  }) async {
    if (_currentSession == null) return null;

    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response = await _apiService.activateDailyRetry(
        roomId: roomId,
        action: action,
        mode: mode ?? _currentMode,
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
    String? mode,
  }) async {
    final response = await _apiService.purchaseDailyGameHint(
      roomId: roomId,
      hintType: hintType,
      mode: mode ?? _currentMode,
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
  Future<void> loadLeaderboard(
    String roomId, {
    bool silent = false,
    String? mode,
  }) async {
    try {
      if (!silent) {
        _isLoading = true;
        _errorMessage = null;
        notifyListeners();
      }

      final response = await _apiService.getLeaderboard(
        roomId,
        mode: mode ?? _currentMode,
      );
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
  Future<void> connectToChat(String roomId, {String? mode}) async {
    // Cancel any existing subscription
    await _wsSubscription?.cancel();

    // Subscribe to WebSocket events
    _wsSubscription = _webSocketService.events.listen(_handleWebSocketEvent);

    // Connect to the room
    final resolvedMode = mode ?? _currentMode;
    final connected = await _webSocketService.connect(
      roomId,
      mode: resolvedMode,
    );
    _isWebSocketConnected = connected;
    _currentChatRoomId = roomId;
    _currentMode = resolvedMode;
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
    _markAllPendingMessagesFailed('Connection lost. Tap retry.');
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
        _markAllPendingMessagesFailed('Connection lost. Tap retry.');
        notifyListeners();
        break;

      case WebSocketEventType.message:
        final message = event.data as Message;
        _reconcileIncomingMessage(message);
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
        _markAllPendingMessagesFailed(
          _errorMessage ?? 'Message failed to send.',
        );
        notifyListeners();
        break;
    }
  }

  /// Load messages (initial load via REST API)
  Future<void> loadMessages(
    String roomId, {
    String? mode,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await _apiService.getMessages(
        roomId: roomId,
        mode: mode ?? _currentMode,
        limit: limit,
        offset: offset,
      );

      final serverMessages = (response['messages'] as List)
          .map((msg) => Message.fromJson(msg as Map<String, dynamic>))
          .toList();
      _messages = _mergeServerMessages(serverMessages);

      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Send a message via WebSocket (real-time) or REST API (fallback).
  Future<void> sendMessage(
    String roomId,
    String message, {
    String? mode,
    required User currentUser,
    String? clientMessageId,
  }) async {
    final resolvedClientMessageId = clientMessageId ?? _uuid.v4();
    final resolvedMode = mode ?? _currentMode;
    _upsertLocalMessage(
      Message.pending(
        clientMessageId: resolvedClientMessageId,
        user: currentUser,
        message: message,
      ),
    );
    notifyListeners();

    if (_isWebSocketConnected) {
      _schedulePendingMessageTimeout(resolvedClientMessageId);
      final sent = _webSocketService.sendMessage(
        message,
        clientMessageId: resolvedClientMessageId,
      );
      if (sent) {
        return;
      }
      _cancelPendingMessageTimeout(resolvedClientMessageId);
    }

    try {
      final response = await _apiService.sendMessage(
        roomId: roomId,
        message: message,
        mode: resolvedMode,
        clientMessageId: resolvedClientMessageId,
      );
      _reconcileIncomingMessage(Message.fromJson(response));
    } catch (e) {
      _errorMessage = e.toString();
      _markMessageFailed(resolvedClientMessageId, _errorMessage!);
    }
  }

  Future<void> retryMessage(
    String roomId,
    Message message, {
    String? mode,
    required User currentUser,
  }) async {
    final clientMessageId = message.clientMessageId;
    if (clientMessageId == null) return;

    _upsertLocalMessage(
      message.copyWith(
        user: currentUser,
        deliveryStatus: MessageDeliveryStatus.sending,
        clearFailureReason: true,
      ),
    );
    notifyListeners();

    await sendMessage(
      roomId,
      message.message,
      mode: mode,
      currentUser: currentUser,
      clientMessageId: clientMessageId,
    );
  }

  List<Message> _mergeServerMessages(List<Message> serverMessages) {
    final unresolvedMessages = _messages.where((message) {
      if (!message.isSending && !message.isFailed) {
        return false;
      }

      return !serverMessages.any(
        (serverMessage) =>
            serverMessage.id == message.id ||
            (message.clientMessageId != null &&
                serverMessage.clientMessageId == message.clientMessageId),
      );
    }).toList();

    return [...unresolvedMessages, ...serverMessages];
  }

  void _upsertLocalMessage(Message message) {
    final existingIndex = _messages.indexWhere(
      (existingMessage) =>
          existingMessage.id == message.id ||
          (message.clientMessageId != null &&
              existingMessage.clientMessageId == message.clientMessageId),
    );

    if (existingIndex >= 0) {
      _messages[existingIndex] = message;
      return;
    }

    _messages.insert(0, message);
  }

  void _reconcileIncomingMessage(Message message) {
    final existingIndex = _messages.indexWhere(
      (existingMessage) =>
          existingMessage.id == message.id ||
          (message.clientMessageId != null &&
              existingMessage.clientMessageId == message.clientMessageId),
    );
    final resolvedMessage = message.copyWith(
      deliveryStatus: MessageDeliveryStatus.sent,
      clearFailureReason: true,
    );

    if (existingIndex >= 0) {
      _messages[existingIndex] = resolvedMessage;
    } else {
      _messages.insert(0, resolvedMessage);
    }

    if (message.clientMessageId != null) {
      _cancelPendingMessageTimeout(message.clientMessageId!);
    }
    notifyListeners();
  }

  void _markMessageFailed(String clientMessageId, String errorMessage) {
    final existingIndex = _messages.indexWhere(
      (message) => message.clientMessageId == clientMessageId,
    );
    if (existingIndex < 0) {
      return;
    }

    _messages[existingIndex] = _messages[existingIndex].copyWith(
      deliveryStatus: MessageDeliveryStatus.failed,
      failureReason: errorMessage,
    );
    _cancelPendingMessageTimeout(clientMessageId);
    notifyListeners();
  }

  void _markAllPendingMessagesFailed(String errorMessage) {
    var hasChanges = false;
    for (var i = 0; i < _messages.length; i += 1) {
      if (_messages[i].isSending) {
        _messages[i] = _messages[i].copyWith(
          deliveryStatus: MessageDeliveryStatus.failed,
          failureReason: errorMessage,
        );
        hasChanges = true;
      }
    }

    if (hasChanges) {
      _clearPendingMessageTimeouts();
    }
  }

  void _schedulePendingMessageTimeout(String clientMessageId) {
    _cancelPendingMessageTimeout(clientMessageId);
    _pendingMessageTimeouts[clientMessageId] = Timer(
      _pendingMessageTimeout,
      () =>
          _markMessageFailed(clientMessageId, 'Message timed out. Tap retry.'),
    );
  }

  void _cancelPendingMessageTimeout(String clientMessageId) {
    _pendingMessageTimeouts.remove(clientMessageId)?.cancel();
  }

  void _clearPendingMessageTimeouts() {
    for (final timer in _pendingMessageTimeouts.values) {
      timer.cancel();
    }
    _pendingMessageTimeouts.clear();
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
      final requestId = ++_playSnippetRequestId;
      try {
        final playbackFuture = _audioService.playSnippetByNumber(
          _currentSession!.currentSnippet,
          onPlaybackStarted: notifyListeners,
          onPlaybackStopped: notifyListeners,
        );
        await playbackFuture;
      } catch (e) {
        try {
          final refreshedSession = await _refreshAndLoadAudio(_currentSession!);
          final retryFuture = _audioService.playSnippetByNumber(
            refreshedSession.currentSnippet,
            onPlaybackStarted: notifyListeners,
            onPlaybackStopped: notifyListeners,
          );
          await retryFuture;
        } catch (_) {
          if (requestId == _playSnippetRequestId) {
            _errorMessage = 'Failed to play audio: $e';
            notifyListeners();
            rethrow;
          }
        }
      }
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> stopPlayback() async {
    _playSnippetRequestId += 1;
    await _audioService.stop();
    notifyListeners();
  }

  /// Clear guess result
  void clearGuessResult() {
    _guessResult = null;
    notifyListeners();
  }

  /// Reset game state
  void reset() {
    _clearPendingMessageTimeouts();
    _currentSession = null;
    _leaderboard = [];
    _messages = [];
    _errorMessage = null;
    _guessResult = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _clearPendingMessageTimeouts();
    _wsSubscription?.cancel();
    _webSocketService.dispose();
    _audioService.dispose();
    super.dispose();
  }
}
