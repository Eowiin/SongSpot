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
  int? _artistDeezerId;
  bool _mix = false;
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
  int? _artistPoolSize;
  bool _isJudging = false;
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
  int _searchRequestId = 0;

  // Getters
  app_models.Category? get category => _category;
  String? get artistFilter => _artistFilter;
  int? get artistDeezerId => _artistDeezerId;

  /// True for an all-genre run, drawn across every category.
  bool get isMix => _mix;

  /// The genre the run is scored under. All-genre runs get their own key, so
  /// they have their own leaderboard instead of joining artist runs under none.
  String? get _genre => _mix ? 'mix' : _category?.category;

  /// How many tracks the chosen artist has, once the first round has landed.
  /// Null for category play, and for artists the server did not report on.
  int? get artistPoolSize => _artistPoolSize;

  /// True while a guess is with the server. The guess field is disabled
  /// meanwhile so one round cannot be answered twice.
  bool get isJudging => _isJudging;
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
    int? artistDeezerId,
    bool mix = false,
    Difficulty difficulty = Difficulty.medium,
    bool isGuest = false,
  }) {
    _category = category;
    _artistFilter = artistFilter;
    _artistDeezerId = artistDeezerId;
    _mix = mix;
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
    _resetSearch();
    _snippetPlaysForTrack = 0;
    _runEndLogged = false;
    notifyListeners();
    _analytics.sessionStarted(
      mode: 'solo',
      genre: _genre,
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
      _resetSearch();
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
    _resetSearch();
    _snippetPlaysForTrack = 0;
    notifyListeners();

    try {
      final data = await _api.getNextSong(
        mix: _mix,
        playlist: _category?.id,
        artist: _artistFilter,
        artistDeezerId: _artistDeezerId,
        excludeIds: List.from(_seenTrackIds),
      );
      _currentTrack = Track.fromJson(data);
      _artistPoolSize = _currentTrack!.poolSize ?? _artistPoolSize;
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
          // copyWith, not a rebuild from JSON: the round token has to survive
          // or the guess can no longer be judged.
          _currentTrack = _currentTrack!.copyWith(previewUrl: newUrl);
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
        mix: _mix,
        playlist: _category?.id,
        artist: _artistFilter,
        artistDeezerId: _artistDeezerId,
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
              _prefetchedTrack = _prefetchedTrack!.copyWith(previewUrl: newUrl);
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
      genre: _genre,
      artistFilter: _artistFilter ?? '',
      difficulty: _difficulty.name,
      songsPlayed: _songsPlayed,
      songsCorrect: _songsCorrect,
      bestStreak: _bestStreak,
      totalScore: _totalScore,
    ).catchError((_) => <String, dynamic>{});
  }

  // ── Guess logic ──────────────────────────────────────────────────────────

  /// Send a guess to the server and reveal the answer it returns.
  ///
  /// The comparison used to happen here, as `guessed.id == current.id`. That
  /// only works while every song has exactly one row; against the open
  /// catalogue one song has many Deezer releases, so a player who picked the
  /// single when the round was playing the album cut was told they were wrong.
  /// The server owns the rule now, which also means a bad call can be fixed
  /// without shipping a new build.
  Future<void> submitGuess(Track guessedTrack) =>
      _judge(guessTrackId: guessedTrack.id, gaveUp: false);

  Future<void> giveUp() => _judge(guessTrackId: null, gaveUp: true);

  Future<void> _judge({required String? guessTrackId, required bool gaveUp}) async {
    final track = _currentTrack;
    if (track == null || _revealAnswer || _isJudging) return;

    _audio.stop();
    _isPlaying = false;
    _isSnippetSounding = false;

    final bool isCorrect;
    if (track.roundToken == null) {
      // No token: an older server, or a round rebuilt from cache. Fall back to
      // the identity comparison rather than refusing to score the round.
      isCorrect = !gaveUp && guessTrackId == track.id;
    } else {
      _isJudging = true;
      notifyListeners();
      try {
        final result = await _api.submitGuess(
          roundToken: track.roundToken!,
          guessTrackId: guessTrackId,
        );
        isCorrect = result['correct'] == true;
        final answer = result['answer'];
        if (answer is Map<String, dynamic>) {
          _currentTrack = track.revealedWith(answer);
        }
      } catch (e) {
        // The round is not consumed: a dropped connection must not cost a
        // life, and the player can submit the same guess again.
        debugPrint('Guess submission failed: $e');
        _isJudging = false;
        _trackError = e.toString();
        notifyListeners();
        return;
      } finally {
        _isJudging = false;
      }
    }

    _songsPlayed++;
    _lastGuessResult = isCorrect ? GuessResult.correct : GuessResult.wrong;
    _revealAnswer = true;
    _resetSearch();
    _trackError = null;

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
      gaveUp: gaveUp,
      songIndex: _songsPlayed,
      difficulty: _difficulty.name,
    );
    notifyListeners();
  }

  // ── Track search (autocomplete) ──────────────────────────────────────────

  /// Empty the suggestion list and disown whatever search is still in flight.
  ///
  /// Both halves matter. The debounce timer only cancels a request not yet
  /// sent; once it is out on the wire nothing can call it back, and Deezer is
  /// slow often enough that responses come back out of order. Bumping the id
  /// is how a superseded response is recognised and dropped — otherwise the
  /// answer to `ro` lands after the answer to `rosalia` and overwrites it, or
  /// lands after the round has moved on and fills the box under the next song.
  void _resetSearch() {
    _searchDebounce?.cancel();
    _searchRequestId++;
    _searchResults = [];
    _isSearching = false;
  }

  void searchTracks(String query) {
    _resetSearch();
    final requestId = _searchRequestId;
    if (query.length < 2) {
      notifyListeners();
      return;
    }
    _isSearching = true;
    notifyListeners();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      List<Track> results;
      try {
        final json = await _api.searchTracks(query);
        results = json
            .map((j) => Track.fromJson(j as Map<String, dynamic>))
            .toList();
      } catch (_) {
        results = [];
      }
      if (requestId != _searchRequestId) return;
      _searchResults = results;
      _isSearching = false;
      notifyListeners();
    });
  }

  void clearSearch() {
    _resetSearch();
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
        genre: _genre,
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
