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
  String? _activeUrl;
  String? _prefetchUrl;
  bool _sourceReleased = false;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;

  AudioPlayer get _active => _usingA ? _playerA : _playerB;
  AudioPlayer get _prefetch => _usingA ? _playerB : _playerA;

  bool get isPlaying => _isPlaying;

  /// Every transition of [isPlaying], from every path — a snippet ending on
  /// its own, [stop], an interruption, a failure, a superseded request.
  ///
  /// The `onPlaybackStopped` callback below only fires on the one path that
  /// runs to the end of [playSnippet]; a caller that mirrors its own "is
  /// playing" flag from that callback alone gets stuck showing the wrong state
  /// whenever playback ends some other way. Listen to this instead.
  final ValueNotifier<bool> playing = ValueNotifier<bool>(false);

  /// True only once the player is really producing sound. [playing] flips as
  /// soon as a snippet is asked for — the button has to lock right away — but
  /// the first sample can land a few hundred milliseconds later while the
  /// platform buffers. Anything that has to line up with what is heard, such
  /// as the progress rail under the play button, runs off this instead.
  final ValueNotifier<bool> sounding = ValueNotifier<bool>(false);

  void _setPlaying(bool value, {void Function()? onChanged}) {
    if (!value) sounding.value = false;
    if (_isPlaying == value) return;
    _isPlaying = value;
    playing.value = value;
    onChanged?.call();
  }

  /// How long to wait for the player to report that it has started before
  /// running the snippet anyway: a signal that never comes must not hang the
  /// round. The source is already loaded by the time we get here, so a start
  /// that has not been reported within a second is not coming.
  static const Duration _startBudget = Duration(seconds: 1);

  /// Resolves when the player actually starts playing. just_audio's state
  /// stream replays its latest value on listen, so a start that has already
  /// happened resolves straight away.
  ///
  /// Platform players only — on the web `ready` does not mean what this needs
  /// it to mean; see the web branch of [playSnippet].
  Future<void> _awaitAudibleStart(AudioPlayer player) async {
    try {
      await player.playerStateStream
          .firstWhere(
            (s) =>
                s.playing &&
                (s.processingState == ProcessingState.ready ||
                    // A very short clip can be over before we get here; that
                    // is a start too, and waiting on one that has passed
                    // would stall the snippet.
                    s.processingState == ProcessingState.completed),
          )
          .timeout(_startBudget);
    } catch (_) {
      // Timed out, or the stream closed under us — carry on regardless.
    }
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
    _sourceReleased = true;
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
      // Recorded only once this request is known to be the live one: a stale
      // load whose setUrl lands late must not claim the player it no longer
      // owns, or a replay would reload the wrong track.
      _activeUrl = url;
      _sourceReleased = false;
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
      _prefetchUrl = url;
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
    _activeUrl = _prefetchUrl;
    _prefetchUrl = null;
    _sourceReleased = false;
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
      // A previous snippet was ended with stop(), which deactivates the
      // platform player and drops the loaded source. just_audio does reload it
      // on the next play(), but asynchronously — and on the web the snippet
      // timer below starts at the tap, so the reload is still in flight when
      // the timer pauses the player and the round goes silent. Reloading here
      // is the same work, in the one place it can be awaited.
      if (_sourceReleased && _activeUrl != null) {
        debugPrint('[AudioService] playSnippet: reloading released source');
        await player.setUrl(_activeUrl!).timeout(const Duration(seconds: 15));
        _sourceReleased = false;
        if (requestId != _playbackRequestId) return;
      }
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
        // The web player has no setClip, so the timer below is what cuts the
        // snippet — and it starts here, at the tap, with no wait for the first
        // sample. Waiting was tried and measured in Chrome: on the web
        // `ProcessingState.ready` is the element's `canplaythrough`, meaning
        // enough is buffered to play the whole preview through, not that sound
        // has started. It therefore cannot report the real start — when the
        // source is loaded it is already `ready` at the tap (the wait resolved
        // in ~1ms, the sound came ~110ms later), and when the buffer is thin
        // the element plays while just_audio still says `buffering`, so the
        // wait runs out its whole budget and the timer then hands out that
        // much extra song: a 1s snippet was heard for 1.9s on a starved
        // connection. Starting at the tap costs the browser's start latency
        // off the front of the snippet instead, which is the safe direction —
        // Hard gets slightly less than its second, never more.
        sounding.value = true;
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

        await _awaitAudibleStart(player);
        if (requestId != _playbackRequestId) return;
        sounding.value = true;

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

  // Callers wire this straight into sync handlers (submitGuess, giveUp,
  // screen dispose) without awaiting, so an escaping error would surface as an
  // unhandled async error and kill the app. iOS throws PlatformException
  // 561015905 ('!pla', session activation failed) here whenever the session
  // cannot be activated — routinely when the app is already in the background —
  // and there is nothing to recover: playback is being torn down anyway.
  // _setPlaying stays outside the guard so the play button is released either way.
  Future<void> stop() async {
    _playbackRequestId += 1;
    _sourceReleased = true;
    try {
      await _active.stop();
      await _active.seek(Duration.zero);
    } catch (e) {
      debugPrint('[AudioService] stop: FAILED $e');
    }
    _setPlaying(false);
  }

  // AudioService is a singleton — the players must never be disposed.
  // Call stop() when leaving a screen instead.
  Future<void> dispose() async {
    await stop();
  }
}
