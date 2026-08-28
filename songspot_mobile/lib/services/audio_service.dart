import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

class AudioService {
  AudioService._();
  static final AudioService _instance = AudioService._();
  factory AudioService() => _instance;

  final AudioPlayer _playerA = AudioPlayer();
  final AudioPlayer _playerB = AudioPlayer();
  bool _usingA = true;
  bool _prefetchReady = false;
  int _playbackRequestId = 0;
  int _prefetchRequestId = 0;
  bool _isPlaying = false;
  bool _isInitialized = false;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;

  AudioPlayer get _active => _usingA ? _playerA : _playerB;
  AudioPlayer get _prefetch => _usingA ? _playerB : _playerA;

  bool get isPlaying => _isPlaying;

  void _setPlaying(bool value, {void Function()? onChanged}) {
    if (_isPlaying == value) return;
    _isPlaying = value;
    onChanged?.call();
  }

  Future<void> initializeAudioSession() async {
    if (_isInitialized) return;
    // audio_session has no web implementation; the browser owns the audio
    // focus policy. Mark it done so we don't retry on every load.
    if (kIsWeb) {
      _isInitialized = true;
      return;
    }
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      // A phone call, Siri, or another app (Spotify) grabbing audio focus
      // pauses the player without ever reaching `completed`. Without this the
      // snippet would only end at playSnippet's wall-clock ceiling, leaving the
      // play button stuck for the whole budget. Stop on the interruption's
      // start so the button is released at once; do not auto-resume on end —
      // the player taps play again.
      _interruptionSub ??= session.interruptionEventStream.listen((event) {
        if (event.begin) {
          unawaited(haltForInterruption());
        }
      });
      _isInitialized = true;
    } catch (_) {}
  }

  /// End the current snippet immediately because the app was backgrounded or
  /// audio was interrupted. Stopping the active player drives it to `idle`,
  /// which resolves playSnippet's completion future on its normal path — so the
  /// caller's onPlaybackStopped fires and the play button is released. The
  /// request id is deliberately left untouched so that path is not skipped.
  Future<void> haltForInterruption() async {
    if (!_isPlaying) return;
    debugPrint('[AudioService] haltForInterruption');
    try {
      await _active.stop();
    } catch (_) {}
  }

  /// Load a URL into the active player (no playback yet). Aborts any in-progress prefetch.
  Future<void> loadAudio(String url) async {
    final requestId = ++_playbackRequestId;
    _prefetchReady = false;
    ++_prefetchRequestId;
    debugPrint('[AudioService] loadAudio: url=$url requestId=$requestId');
    try {
      await initializeAudioSession();
      _setPlaying(false);
      await _active.stop();
      await _active.setUrl(url).timeout(const Duration(seconds: 15));
      if (requestId != _playbackRequestId) {
        debugPrint('[AudioService] loadAudio: stale, aborting');
        return;
      }
      debugPrint('[AudioService] loadAudio: ready');
    } catch (e) {
      debugPrint('[AudioService] loadAudio: FAILED $e');
      throw Exception('Failed to load audio: $e');
    }
  }

  /// Silently buffer a URL in the prefetch player. Does not affect active playback.
  /// Returns true if buffering succeeded, false otherwise.
  Future<bool> prefetchAudio(String url) async {
    final requestId = ++_prefetchRequestId;
    _prefetchReady = false;
    debugPrint('[AudioService] prefetchAudio: url=$url requestId=$requestId');
    try {
      await _prefetch.stop();
      await _prefetch.setUrl(url).timeout(const Duration(seconds: 15));
      if (requestId != _prefetchRequestId) {
        debugPrint('[AudioService] prefetchAudio: stale, aborting');
        return false;
      }
      _prefetchReady = true;
      debugPrint('[AudioService] prefetchAudio: ready');
      return true;
    } catch (e) {
      debugPrint('[AudioService] prefetchAudio: FAILED $e');
      return false;
    }
  }

  /// Swap the prefetch player to active. Returns true if prefetch was ready (instant swap).
  /// Returns false if not ready — caller must fall back to loadAudio().
  bool swapToPrefetch() {
    if (!_prefetchReady) return false;
    _usingA = !_usingA;
    _prefetchReady = false;
    ++_prefetchRequestId;
    debugPrint('[AudioService] swapToPrefetch: swapped');
    return true;
  }

  /// Play a snippet of [duration] from the active player.
  /// If [duration] is null, plays the full clip until natural end.
  Future<void> playSnippet({
    Duration? duration = const Duration(seconds: 1),
    void Function()? onPlaybackStopped,
  }) async {
    debugPrint('[AudioService] playSnippet: duration=$duration');
    final requestId = ++_playbackRequestId;
    // Captured once: swapToPrefetch() can flip `_active` mid-playback.
    final player = _active;
    try {
      if (kIsWeb) {
        // just_audio's web backend ignores setClip's end boundary and plays the
        // whole ~30s preview, which would hand the player the answer. On web the
        // snippet is bounded with an explicit timer instead (see below).
        await player.seek(Duration.zero);
      } else {
        await player.setClip(start: Duration.zero, end: duration);
      }
      if (requestId != _playbackRequestId) return;

      if (kIsWeb && duration != null) {
        _setPlaying(true);
        // Deliberately not awaited: play() only resolves once playback stops,
        // which without setClip is the end of the full preview.
        unawaited(
          player.play().catchError((Object e) {
            debugPrint('[AudioService] playSnippet: play() failed $e');
          }),
        );
        await Future<void>.delayed(duration);
        if (requestId != _playbackRequestId) return;
        try {
          await player.pause();
          await player.seek(Duration.zero);
        } catch (_) {}
      } else {
        // Subscribe *before* play(). play()'s future only resolves once
        // playback has already stopped, so a listener attached after it would
        // miss the `completed` event and hang until the timeout fired.
        // onError swallows late stream errors so they can never surface as an
        // unhandled async error after we have stopped listening.
        final done = player.processingStateStream
            .firstWhere(
              (s) => s == ProcessingState.completed || s == ProcessingState.idle,
            )
            .then<void>((_) {}, onError: (Object _) {});

        _setPlaying(true);
        // Deliberately not awaited — `done` already tracks the end of playback.
        unawaited(
          player.play().catchError((Object e) {
            debugPrint('[AudioService] playSnippet: play() failed $e');
          }),
        );

        // Wall-clock ceiling. An interruption (incoming call, backgrounding,
        // lost audio focus) pauses the player without ever reaching
        // `completed`, which would otherwise leave the play button stuck.
        // Hitting the ceiling is a normal end of snippet, never an error.
        final budget =
            (duration ?? const Duration(seconds: 30)) +
            const Duration(seconds: 5);
        await done.timeout(
          budget,
          onTimeout: () async {
            debugPrint('[AudioService] playSnippet: budget elapsed, pausing');
            if (requestId == _playbackRequestId) {
              try {
                await player.pause();
              } catch (_) {}
            }
          },
        );
      }

      if (requestId == _playbackRequestId) {
        _setPlaying(false, onChanged: onPlaybackStopped);
      }
    } catch (e) {
      // Real failures (expired source, decode error) still propagate: callers
      // refresh the preview URL and retry on them.
      debugPrint('[AudioService] playSnippet: FAILED $e');
      if (requestId == _playbackRequestId) {
        _setPlaying(false, onChanged: onPlaybackStopped);
      }
      rethrow;
    }
  }

  Future<void> stop() async {
    _playbackRequestId += 1;
    await _active.stop();
    await _active.seek(Duration.zero);
    _setPlaying(false);
  }

  // AudioService is a singleton — the players must never be disposed.
  // Call stop() when leaving a screen instead.
  Future<void> dispose() async {
    await stop();
  }
}
