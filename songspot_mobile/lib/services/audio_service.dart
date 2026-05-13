import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isInitialized = false;
  int _playbackRequestId = 0;

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

  /// Load a URL into the player (no playback yet).
  Future<void> loadAudio(String url) async {
    final requestId = ++_playbackRequestId;
    try {
      await initializeAudioSession();
      _setPlaying(false);
      await _player.stop();
      await _player.setUrl(url).timeout(const Duration(seconds: 15));
      if (requestId != _playbackRequestId) return;
    } catch (e) {
      throw Exception('Failed to load audio: $e');
    }
  }

  /// Play a snippet of audio up to [duration] (frame-accurate via setClip, no wall-clock timer).
  /// setClip is re-applied on every call to reset the player from any completed state.
  /// We wait for processingState.completed rather than awaiting play() directly,
  /// because play() resolves as soon as playback starts, not when it ends.
  Future<void> playSnippet({
    Duration duration = const Duration(seconds: 1),
    void Function()? onPlaybackStopped,
  }) async {
    final requestId = ++_playbackRequestId;
    try {
      await _player.setClip(
        start: Duration.zero,
        end: duration,
      );
      if (requestId != _playbackRequestId) return;

      // Subscribe before play() to avoid missing the completed event.
      // Also accepts idle so that stop() or an audio interruption resolves
      // this immediately rather than hanging until the 5s timeout.
      // Safe to include idle here because setClip is already awaited above —
      // we won't catch the transient idle emitted during clip setup.
      // Timeout = snippet length + 5s buffer so longer snippets (Easy: 15s) don't time out mid-play.
      final doneFuture = _player.processingStateStream
          .firstWhere((s) =>
              s == ProcessingState.completed || s == ProcessingState.idle)
          .timeout(duration + const Duration(seconds: 5));

      _setPlaying(true);
      _player.play(); // intentionally not awaited

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
    await _player.stop();
    await _player.seek(Duration.zero);
    _setPlaying(false);
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
