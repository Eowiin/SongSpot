import 'package:flutter/foundation.dart';
import '../models/game_session.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';

class GameProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final AudioService _audioService = AudioService();

  GameSession? _currentSession;
  List<LeaderboardEntry> _leaderboard = [];
  List<Message> _messages = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _guessResult;

  GameSession? get currentSession => _currentSession;
  List<LeaderboardEntry> get leaderboard => _leaderboard;
  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get guessResult => _guessResult;
  AudioService get audioService => _audioService;

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
      final previewUrl = _currentSession!.dailySong.track.previewUrl;
      if (previewUrl.isEmpty) {
        throw Exception('No preview URL available for this track');
      }

      await _audioService.loadAudio(previewUrl);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load game: $e';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
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

  /// Load messages
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

  /// Send a message
  Future<bool> sendMessage(String roomId, String message) async {
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
    _audioService.dispose();
    super.dispose();
  }
}
