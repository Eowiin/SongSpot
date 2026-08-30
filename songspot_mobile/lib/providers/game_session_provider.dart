import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/track.dart';
import '../models/game_score.dart';
import '../models/category.dart' as app_models;
import '../services/analytics_service.dart';
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
  GameSessionProvider() {
    // Mirror the player's real state rather than inferring it from the one
    // callback that fires when a snippet runs to its end. Playback also stops
    // on a guess, on a new track, on an interruption and on failure; before
    // this the play button could be left showing the wrong state after any of
    // those, and no further press would put it right.
    _audio.playing.addListener(_onAudioPlayingChanged);
    _audio.sounding.addListener(_onAudioSoundingChanged);
  }

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
  bool _isSnippetSounding = false;

  // Guess state
  GuessResult _lastGuessResult = GuessResult.none;
  bool _revealAnswer = false;

  // Lives
  int _livesRemaining = 3;

  // Session end reason (null = still playing)
  SessionEndReason? _endReason;

  // Session identity (for checkpointing)
  String? _sessionUuid;

  // Prefetch state
  Track? _prefetchedTrack;
  final AnalyticsService _analytics = AnalyticsService();
  int _snippetPlaysForTrack = 0;
  bool _runEndLogged = false;

  bool _isPrefetching = false;
  bool _prefetchPoolExhausted = false;

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

  /// True only while the snippet is actually coming out of the speaker, as
  /// opposed to [isPlaying], which also covers the buffering gap after the
  /// tap. The progress rail runs off this so it cannot get ahead of the sound.
  bool get isSnippetSounding => _isSnippetSounding;
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
    _sessionUuid = const Uuid().v4();
    _prefetchedTrack = null;
    _isPrefetching = false;
    _prefetchPoolExhausted = false;
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
    _snippetPlaysForTrack = 0;
    _runEndLogged = false;
    notifyListeners();
    _analytics.sessionStarted(
      mode: 'solo',
      genre: category?.category,
      artist: artistFilter,
      difficulty: difficulty.name,
    );
  }

  Future<void> loadNextSong() async {
    // Pool already known exhausted from silent prefetch
    if (_prefetchPoolExhausted) {
      _endReason = SessionEndReason.poolCleared;
      _currentTrack = null;
      _isLoadingTrack = false;
      notifyListeners();
      return;
    }

    // Consume prefetch if available
    if (_prefetchedTrack != null) {
      _lastGuessResult = GuessResult.none;
      _revealAnswer = false;
      _searchResults = [];
      _snippetPlaysForTrack = 0;
      _currentTrack = _prefetchedTrack;
      _seenTrackIds.add(_currentTrack!.id);
      _prefetchedTrack = null;

      final swapped = _audio.swapToPrefetch();
      if (!swapped && _currentTrack!.previewUrl != null) {
        _isLoadingTrack = true;
        notifyListeners();
        await _loadAudioWithRetry(_currentTrack!.previewUrl!, _currentTrack!.id);
        _isLoadingTrack = false;
      }
      notifyListeners();
      prefetchNextSong();
      return;
    }

    // Full load path
    _isLoadingTrack = true;
    _trackError = null;
    _lastGuessResult = GuessResult.none;
    _revealAnswer = false;
    _searchResults = [];
    _snippetPlaysForTrack = 0;
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
      prefetchNextSong();
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
      var recovered = false;
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
          recovered = true;
        }
      } catch (retryError) {
        debugPrint('Audio retry also failed: $retryError');
        // Non-fatal — user can tap Play manually
      }
      _analytics.audioLoadFailed(retrySucceeded: recovered);
    }
  }

  // Returns false when playback failed (source expired, network drop, interruption).
  Future<bool> _playSnippet({bool fullPreview = false}) async {
    if (_currentTrack?.previewUrl == null) return false;
    _isPlaying = true;
    notifyListeners();
    try {
      await _audio.playSnippet(
        duration: fullPreview ? null : _difficulty.snippetDuration,
        onPlaybackStopped: () {
          _isPlaying = false;
          _isSnippetSounding = false;
          notifyListeners();
        },
      );
      // playSnippet returns once the snippet is over — or immediately, without
      // firing onPlaybackStopped, when a newer request superseded this one.
      // Resync so that path cannot leave the button stuck on "playing".
      if (_isPlaying != _audio.isPlaying) {
        _isPlaying = _audio.isPlaying;
        notifyListeners();
      }
      return true;
    } catch (e) {
      debugPrint('Playback error: $e');
      _isPlaying = false;
      _isSnippetSounding = false;
      notifyListeners();
      return false;
    }
  }

  // Never throws: callers wire this straight to onTap, so an escaping error
  // would surface as an unhandled async error and kill the app.
  Future<void> replaySnippet() async {
    if (_isPlaying) return;
    // Counted before the attempt: a play that fails is still a play the user
    // asked for, and the failure shows up as audio_load_failed.
    _analytics.snippetPlayed(
      difficulty: _difficulty.name,
      replayCount: _snippetPlaysForTrack++,
    );
    if (await _playSnippet(fullPreview: _revealAnswer)) return;

    // Preview URLs expire — refresh the source and retry once before giving up.
    final track = _currentTrack;
    if (track?.previewUrl == null) return;
    await _loadAudioWithRetry(track!.previewUrl!, track.id);
    await _playSnippet(fullPreview: _revealAnswer);
  }

  // ── Prefetch ─────────────────────────────────────────────────────────────

  Future<void> prefetchNextSong() async {
    if (_isPrefetching || _endReason != null) return;
    _isPrefetching = true;
    try {
      final data = await _api.getNextSong(
        playlist: _category?.id,
        artist: _artistFilter,
        excludeIds: List.from(_seenTrackIds),
      );
      _prefetchedTrack = Track.fromJson(data);
      if (_prefetchedTrack!.previewUrl != null) {
        final ok = await _audio.prefetchAudio(_prefetchedTrack!.previewUrl!);
        if (!ok) {
          // URL may be stale — refresh from Deezer and retry once
          try {
            final refreshed = await _api.refreshTrackPreview(trackId: _prefetchedTrack!.id);
            final newUrl = refreshed['preview_url'] as String?;
            if (newUrl != null && newUrl.isNotEmpty && newUrl != _prefetchedTrack!.previewUrl) {
              _prefetchedTrack = Track.fromJson({
                'id': _prefetchedTrack!.id,
                'title': _prefetchedTrack!.title,
                'artist': _prefetchedTrack!.artist,
                'preview_url': newUrl,
                'cover_url': _prefetchedTrack!.coverUrl,
                'release_year': _prefetchedTrack!.releaseYear,
                'genre': _prefetchedTrack!.genre,
              });
              await _audio.prefetchAudio(newUrl);
            }
          } catch (_) {
            // Refresh failed — track metadata is still stored, audio will load on demand
          }
        }
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('404') || msg.contains('Not found') || msg.contains('No tracks')) {
        _prefetchPoolExhausted = true;
      }
      _prefetchedTrack = null;
    } finally {
      _isPrefetching = false;
    }
  }

  // ── Checkpointing ────────────────────────────────────────────────────────

  void _checkpoint() {
    if (_isGuest || _sessionUuid == null || _songsPlayed == 0) return;
    _api.submitScore(
      sessionUuid: _sessionUuid,
      isPartial: true,
      genre: _category?.category,
      artistFilter: _artistFilter ?? '',
      difficulty: _difficulty.name,
      songsPlayed: _songsPlayed,
      songsCorrect: _songsCorrect,
      bestStreak: _bestStreak,
      totalScore: _totalScore,
    ).catchError((_) => <String, dynamic>{});
  }

  // ── Guess logic ──────────────────────────────────────────────────────────

  void submitGuess(Track guessedTrack) {
    if (_currentTrack == null || _revealAnswer) return;

    _audio.stop();
    _isPlaying = false;
    _isSnippetSounding = false;

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

    _checkpoint();
    _analytics.guessSubmitted(
      correct: isCorrect,
      gaveUp: false,
      songIndex: _songsPlayed,
      difficulty: _difficulty.name,
    );
    notifyListeners();
  }

  void giveUp() {
    if (_currentTrack == null || _revealAnswer) return;

    _audio.stop();
    _isPlaying = false;
    _isSnippetSounding = false;

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
    _checkpoint();
    _analytics.guessSubmitted(
      correct: false,
      gaveUp: true,
      songIndex: _songsPlayed,
      difficulty: _difficulty.name,
    );
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
    if (!_runEndLogged) {
      _runEndLogged = true;
      _analytics.sessionEnded(
        mode: 'solo',
        songsPlayed: _songsPlayed,
        songsCorrect: _songsCorrect,
        bestStreak: _bestStreak,
        score: _totalScore,
        endReason: (_endReason ?? SessionEndReason.quit).name,
      );
    }
    if (_songsPlayed == 0) return null;

    if (_isGuest) {
      await _saveGuestSessionStats();
      return null;
    }

    try {
      final data = await _api.submitScore(
        sessionUuid: _sessionUuid,
        isPartial: false,
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
    _audio.playing.removeListener(_onAudioPlayingChanged);
    _audio.sounding.removeListener(_onAudioSoundingChanged);
    _audio.stop(); // AudioService is a singleton — never call dispose() on it
    super.dispose();
  }

  void _onAudioPlayingChanged() {
    final playing = _audio.playing.value;
    if (_isPlaying == playing) return;
    _isPlaying = playing;
    notifyListeners();
  }

  void _onAudioSoundingChanged() {
    final sounding = _audio.sounding.value;
    if (_isSnippetSounding == sounding) return;
    _isSnippetSounding = sounding;
    notifyListeners();
  }
}
