import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isInitialized = false;
  Timer? _stopTimer;
  String? _currentUrl;
  int _playbackRequestId = 0;

  bool get isPlaying => _isPlaying;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// Initialize audio session (call this once at app start)
  Future<void> initializeAudioSession() async {
    if (_isInitialized) return;

    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _isInitialized = true;
    } catch (e) {
      // Continue anyway, it might still work
    }
  }

  /// Load audio from URL
  Future<void> loadAudio(String url) async {
    try {
      // Initialize audio session if not already done
      await initializeAudioSession();

      // Ensure we are not playing from a previous session
      _playbackRequestId += 1;
      _stopTimer?.cancel();
      _isPlaying = false;
      await _player.stop();

      // Set the URL and wait for it to load
      _currentUrl = url;
      await _player.setUrl(url);
    } catch (e) {
      throw Exception('Failed to load audio: $e');
    }
  }

  /// Play snippet for a specific duration (in seconds)
  Future<void> playSnippet(double durationInSeconds) async {
    final requestId = ++_playbackRequestId;
    try {
      _stopTimer?.cancel();

      if (_currentUrl == null) {
        throw StateError('Audio must be loaded before playing a snippet.');
      }

      _isPlaying = true;
      await _player.stop();
      await _player.seek(Duration.zero);

      final clipEnd = Duration(
        milliseconds: (durationInSeconds * 1000).round(),
      );

      _stopTimer = Timer(clipEnd, () async {
        if (requestId != _playbackRequestId) return;
        await _player.stop();
        await _player.seek(Duration.zero);
      });

      await _player.play();
      if (requestId == _playbackRequestId) {
        _stopTimer?.cancel();
        _stopTimer = null;
        _isPlaying = false;
      }
    } catch (e) {
      if (requestId == _playbackRequestId) {
        _stopTimer?.cancel();
        _stopTimer = null;
        _isPlaying = false;
      }
      throw Exception('Failed to play snippet: $e');
    }
  }

  /// Stop playback
  Future<void> stop({bool cancelTimer = true}) async {
    _playbackRequestId += 1;
    if (cancelTimer) {
      _stopTimer?.cancel();
      _stopTimer = null;
    }
    await _player.stop();
    await _player.seek(Duration.zero);
    _isPlaying = false;
  }

  /// Pause playback
  Future<void> pause() async {
    _playbackRequestId += 1;
    _stopTimer?.cancel();
    _stopTimer = null;
    await _player.pause();
    _isPlaying = false;
  }

  /// Resume playback
  Future<void> resume() async {
    await _player.play();
    _isPlaying = true;
  }

  /// Get current position
  Duration get currentPosition => _player.position;

  /// Get total duration
  Duration? get duration => _player.duration;

  /// Dispose the player
  Future<void> dispose() async {
    _stopTimer?.cancel();
    await _player.dispose();
  }

  /// Play snippet based on snippet number (1-6)
  Future<void> playSnippetByNumber(int snippetNumber) async {
    double duration;
    switch (snippetNumber) {
      case 1:
        duration = 0.2;
        break;
      case 2:
        duration = 0.5;
        break;
      case 3:
        duration = 2.0;
        break;
      case 4:
        duration = 4.0;
        break;
      case 5:
        duration = 8.0;
        break;
      case 6:
        duration = 15.0;
        break;
      default:
        duration = 0.2;
    }
    await playSnippet(duration);
  }
}
