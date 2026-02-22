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
  Map<String, bool> _typingUsers = {}; // userId -> isTyping

  GameSession? get currentSession => _currentSession;
  List<LeaderboardEntry> get leaderboard => _leaderboard;
  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get guessResult => _guessResult;
  AudioService get audioService => _audioService;
  bool get isWebSocketConnected => _isWebSocketConnected;
  Stream<WebSocketEvent> get webSocketEvents => _webSocketService.events;
  List<String> get typingUsernames => _typingUsers.entries
      .where((e) => e.value)
      .map((e) => e.key)
      .toList();

  /// Start or get current game session
  Future<void> startGameSession(String roomId) async {
    try {
      // Clear previous session immediately to avoid showing stale data
      _currentSession = null;
      _leaderboard = [];
      _messages = [];
      _isLoading = true;
      _errorMessage = null;
      _guessResult = null;
      notifyListeners();

      final response = await _apiService.startGameSession(roomId);
      _currentSession = GameSession.fromJson(response);

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

    return GameSession(
      id: session.id,
      user: session.user,
      dailySong: updatedDailySong,
      currentSnippet: session.currentSnippet,
      guessesMade: session.guessesMade,
      correctGuess: session.correctGuess,
      pointsEarned: session.pointsEarned,
      completedAt: session.completedAt,
      createdAt: session.createdAt,
    );
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
      _currentSession = GameSession(
        id: _currentSession!.id,
        user: _currentSession!.user,
        dailySong: _currentSession!.dailySong,
        currentSnippet: newSnippet,
        guessesMade: _currentSession!.guessesMade,
        correctGuess: _currentSession!.correctGuess,
        pointsEarned: _currentSession!.pointsEarned,
        completedAt: _currentSession!.completedAt,
        createdAt: _currentSession!.createdAt,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Submit a guess
  Future<bool> submitGuess({
    required String roomId,
    required String trackId,
  }) async {
    if (_currentSession == null) return false;

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

      if (isCorrect) {
        // Update session with correct guess
        _currentSession = GameSession(
          id: _currentSession!.id,
          user: _currentSession!.user,
          dailySong: _currentSession!.dailySong,
          currentSnippet: _currentSession!.currentSnippet,
          guessesMade: _currentSession!.guessesMade + 1,
          correctGuess: true,
          pointsEarned: response['points_earned'] as int?,
          completedAt: DateTime.now(),
          createdAt: _currentSession!.createdAt,
        );
      } else {
        // Update snippet if incorrect
        final newSnippet = response['current_snippet'] as int?;
        if (newSnippet != null) {
          _currentSession = GameSession(
            id: _currentSession!.id,
            user: _currentSession!.user,
            dailySong: _currentSession!.dailySong,
            currentSnippet: newSnippet,
            guessesMade: _currentSession!.guessesMade + 1,
            correctGuess: false,
            pointsEarned: _currentSession!.pointsEarned,
            completedAt: _currentSession!.completedAt,
            createdAt: _currentSession!.createdAt,
          );
        } else {
          // All snippets used
          _currentSession = GameSession(
            id: _currentSession!.id,
            user: _currentSession!.user,
            dailySong: _currentSession!.dailySong,
            currentSnippet: 6,
            guessesMade: _currentSession!.guessesMade + 1,
            correctGuess: false,
            pointsEarned: 0,
            completedAt: DateTime.now(),
            createdAt: _currentSession!.createdAt,
          );
        }
      }

      _isLoading = false;
      notifyListeners();
      return isCorrect;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Load leaderboard
  Future<void> loadLeaderboard(String roomId) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response = await _apiService.getLeaderboard(roomId);
      _leaderboard = (response['leaderboard'] as List)
          .map((entry) => LeaderboardEntry.fromJson(entry as Map<String, dynamic>))
          .toList();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
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
    notifyListeners();
  }

  /// Disconnect from chat WebSocket
  Future<void> disconnectFromChat() async {
    await _wsSubscription?.cancel();
    _wsSubscription = null;
    await _webSocketService.disconnect();
    _isWebSocketConnected = false;
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
  Future<void> loadMessages(String roomId, {int limit = 50, int offset = 0}) async {
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
      _webSocketService.sendMessage(message);
      return true;
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

        await _audioService.playSnippetByNumber(_currentSession!.currentSnippet);

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
