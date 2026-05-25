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
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _isInitialized = true;
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
    try {
      await _active.setClip(start: Duration.zero, end: duration);
      if (requestId != _playbackRequestId) return;

      final timeout = duration != null
          ? duration + const Duration(seconds: 5)
          : const Duration(seconds: 35);

      final doneFuture = _active.processingStateStream
          .firstWhere((s) =>
              s == ProcessingState.completed || s == ProcessingState.idle)
          .timeout(timeout);

      _setPlaying(true);
      _active.play();

      await doneFuture;

      if (requestId == _playbackRequestId) {
        _setPlaying(false, onChanged: onPlaybackStopped);
      }
    } catch (e) {
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
