import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/track.dart';
import '../models/game_score.dart';
import '../models/category.dart' as app_models;
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/storage_service.dart';

enum GuessResult { correct, wrong, none }

enum Difficulty { easy, medium, hard }

extension DifficultyExt on Difficulty {
  Duration get snippetDuration => switch (this) {
        Difficulty.easy => const Duration(seconds: 15),
        Difficulty.medium => const Duration(seconds: 5),
        Difficulty.hard => const Duration(seconds: 1),
      };

  double get scoreMultiplier => switch (this) {
        Difficulty.easy => 1.0,
        Difficulty.medium => 1.5,
        Difficulty.hard => 2.0,
      };

  String get label => switch (this) {
        Difficulty.easy => 'Easy',
        Difficulty.medium => 'Medium',
        Difficulty.hard => 'Hard',
      };

  String get name => switch (this) {
        Difficulty.easy => 'easy',
        Difficulty.medium => 'medium',
        Difficulty.hard => 'hard',
      };
}

enum SessionEndReason { outOfLives, poolCleared, quit }

class GameSessionProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final AudioService _audio = AudioService();
  final StorageService _storage = StorageService();

  // Session config
  app_models.Category? _category;
  String? _artistFilter;
  Difficulty _difficulty = Difficulty.medium;
  bool _isGuest = false;

  // Current track
  Track? _currentTrack;
  bool _isLoadingTrack = false;
  String? _trackError;

  // Audio
  bool _isPlaying = false;

  // Guess state
  GuessResult _lastGuessResult = GuessResult.none;
  bool _revealAnswer = false;

  // Lives
  int _livesRemaining = 3;

  // Session end reason (null = still playing)
  SessionEndReason? _endReason;

  // Session stats (in memory, submitted at end)
  int _songsPlayed = 0;
  int _songsCorrect = 0;
  int _currentStreak = 0;
  int _bestStreak = 0;
  int _totalScore = 0;
  final List<String> _seenTrackIds = [];

  // Guess autocomplete
  List<Track> _searchResults = [];
  bool _isSearching = false;
  Timer? _searchDebounce;

  // Getters
  app_models.Category? get category => _category;
  String? get artistFilter => _artistFilter;
  Difficulty get difficulty => _difficulty;
  Track? get currentTrack => _currentTrack;
  bool get isLoadingTrack => _isLoadingTrack;
  String? get trackError => _trackError;
  bool get isPlaying => _isPlaying;
  GuessResult get lastGuessResult => _lastGuessResult;
  bool get revealAnswer => _revealAnswer;
  int get livesRemaining => _livesRemaining;
  SessionEndReason? get endReason => _endReason;
  int get songsPlayed => _songsPlayed;
  int get songsCorrect => _songsCorrect;
  int get currentStreak => _currentStreak;
  int get bestStreak => _bestStreak;
  int get totalScore => _totalScore;
  List<Track> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  bool get sessionStarted => _songsPlayed > 0 || _currentTrack != null;

  // ── Points calculation ───────────────────────────────────────────────────

  static const int _pointsPerCorrect = 10;
  static const int _streakBonusEvery = 3;
  static const int _streakBonusPoints = 5;

  int get _nextPoints {
    int pts = _pointsPerCorrect;
    if (_currentStreak > 0 && (_currentStreak + 1) % _streakBonusEvery == 0) {
      pts += _streakBonusPoints;
    }
    return (pts * _difficulty.scoreMultiplier).round();
  }

  // ── Session lifecycle ────────────────────────────────────────────────────

  void startSession({
    app_models.Category? category,
    String? artistFilter,
    Difficulty difficulty = Difficulty.medium,
    bool isGuest = false,
  }) {
    _category = category;
    _artistFilter = artistFilter;
    _difficulty = difficulty;
    _isGuest = isGuest;
    _songsPlayed = 0;
    _songsCorrect = 0;
    _currentStreak = 0;
    _bestStreak = 0;
    _totalScore = 0;
    _livesRemaining = 3;
    _endReason = null;
    _seenTrackIds.clear();
    _currentTrack = null;
    _lastGuessResult = GuessResult.none;
    _revealAnswer = false;
    _searchResults = [];
    notifyListeners();
  }

  Future<void> loadNextSong() async {
    _isLoadingTrack = true;
    _trackError = null;
    _lastGuessResult = GuessResult.none;
    _revealAnswer = false;
    _searchResults = [];
    notifyListeners();

    try {
      final data = await _api.getNextSong(
        playlist: _category?.id,
        artist: _artistFilter,
        excludeIds: List.from(_seenTrackIds),
      );
      _currentTrack = Track.fromJson(data);
      _seenTrackIds.add(_currentTrack!.id);

      if (_currentTrack!.previewUrl != null) {
        await _loadAudioWithRetry(_currentTrack!.previewUrl!, _currentTrack!.id);
      }
    } catch (e) {
      final msg = e.toString();
      // 404 = pool exhausted — the user has heard every available song
      if (msg.contains('404') || msg.contains('Not found') || msg.contains('No tracks')) {
        _endReason = SessionEndReason.poolCleared;
        _currentTrack = null;
      } else {
        _trackError = msg;
      }
    } finally {
      _isLoadingTrack = false;
      notifyListeners();
    }
  }

  // Load audio only (no auto-play). On failure, refreshes the preview URL and retries once.
  Future<void> _loadAudioWithRetry(String url, String trackId) async {
    try {
      await _audio.loadAudio(url);
    } catch (e) {
      debugPrint('Audio load failed, refreshing URL: $e');
      try {
        final refreshed = await _api.refreshTrackPreview(trackId: trackId);
        final newUrl = refreshed['preview_url'] as String?;
        if (newUrl != null && newUrl.isNotEmpty && newUrl != url) {
          _currentTrack = Track.fromJson({
            'id': _currentTrack!.id,
            'title': _currentTrack!.title,
            'artist': _currentTrack!.artist,
            'preview_url': newUrl,
            'cover_url': _currentTrack!.coverUrl,
            'release_year': _currentTrack!.releaseYear,
            'genre': _currentTrack!.genre,
          });
          await _audio.loadAudio(newUrl);
        }
      } catch (retryError) {
        debugPrint('Audio retry also failed: $retryError');
        // Non-fatal — user can tap Play manually
      }
    }
  }

  Future<void> _playSnippet() async {
    if (_currentTrack?.previewUrl == null) return;
    _isPlaying = true;
    notifyListeners();
    try {
      await _audio.playSnippet(
        duration: _difficulty.snippetDuration,
        onPlaybackStopped: () {
          _isPlaying = false;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('Playback error: $e');
      _isPlaying = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> replaySnippet() async {
    if (_isPlaying) return;
    await _playSnippet();
  }

  // ── Guess logic ──────────────────────────────────────────────────────────

  void submitGuess(Track guessedTrack) {
    if (_currentTrack == null || _revealAnswer) return;

    _audio.stop();
    _isPlaying = false;

    final isCorrect = guessedTrack.id == _currentTrack!.id;
    _songsPlayed++;
    _lastGuessResult = isCorrect ? GuessResult.correct : GuessResult.wrong;
    _revealAnswer = true;
    _searchResults = [];

    if (isCorrect) {
      _songsCorrect++;
      final pts = _nextPoints;
      _totalScore += pts;
      _currentStreak++;
      if (_currentStreak > _bestStreak) _bestStreak = _currentStreak;
    } else {
      _currentStreak = 0;
      _livesRemaining--;
      if (_livesRemaining <= 0) {
        _livesRemaining = 0;
        _endReason = SessionEndReason.outOfLives;
      }
    }

    notifyListeners();
  }

  void giveUp() {
    if (_currentTrack == null || _revealAnswer) return;

    _audio.stop();
    _isPlaying = false;

    _songsPlayed++;
    _lastGuessResult = GuessResult.wrong;
    _revealAnswer = true;
    _currentStreak = 0;
    _searchResults = [];
    _livesRemaining--;
    if (_livesRemaining <= 0) {
      _livesRemaining = 0;
      _endReason = SessionEndReason.outOfLives;
    }
    notifyListeners();
  }

  // ── Track search (autocomplete) ──────────────────────────────────────────

  void searchTracks(String query) {
    _searchDebounce?.cancel();
    if (query.length < 2) {
      _searchResults = [];
      _isSearching = false;
      notifyListeners();
      return;
    }
    _isSearching = true;
    notifyListeners();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final results = await _api.searchTracks(query);
        _searchResults = results
            .map((j) => Track.fromJson(j as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _searchResults = [];
      } finally {
        _isSearching = false;
        notifyListeners();
      }
    });
  }

  void clearSearch() {
    _searchDebounce?.cancel();
    _searchResults = [];
    _isSearching = false;
    notifyListeners();
  }

  // ── Session end ──────────────────────────────────────────────────────────

  Future<GameScore?> endSession() async {
    await _audio.stop();
    if (_songsPlayed == 0) return null;

    if (_isGuest) {
      await _saveGuestSessionStats();
      return null;
    }

    try {
      final data = await _api.submitScore(
        genre: _category?.category,
        artistFilter: _artistFilter ?? '',
        difficulty: _difficulty.name,
        songsPlayed: _songsPlayed,
        songsCorrect: _songsCorrect,
        bestStreak: _bestStreak,
        totalScore: _totalScore,
      );
      return GameScore.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveGuestSessionStats() async {
    final current = await _storage.getGuestStats();
    await _storage.saveGuestStats(
      bestScore: math.max(current['best_score']!, _totalScore),
      bestStreak: math.max(current['best_streak']!, _bestStreak),
      songsPlayed: current['songs_played']! + _songsPlayed,
      songsCorrect: current['songs_correct']! + _songsCorrect,
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _audio.dispose();
    super.dispose();
  }
}
