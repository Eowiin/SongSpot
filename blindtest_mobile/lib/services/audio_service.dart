import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isInitialized = false;
  Timer? _stopTimer;
  String? _currentUrl;

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
      debugPrint('✅ Audio session initialized successfully');
    } catch (e) {
      debugPrint('⚠️ Failed to initialize audio session: $e');
      // Continue anyway, it might still work
    }
  }

  /// Load audio from URL
  Future<void> loadAudio(String url) async {
    try {
      // Initialize audio session if not already done
      await initializeAudioSession();

      debugPrint('🎵 Loading audio from: $url');

      // Set the URL and wait for it to load
      _currentUrl = url;
      final duration = await _player.setUrl(url);

      if (duration != null) {
        debugPrint('✅ Audio loaded successfully! Duration: ${duration.inSeconds}s');
      } else {
        debugPrint('⚠️ Audio loaded but duration is null');
      }
    } catch (e) {
      debugPrint('❌ Failed to load audio: $e');
      debugPrint('URL was: $url');
      throw Exception('Failed to load audio: $e');
    }
  }

  /// Play snippet for a specific duration (in seconds)
  Future<void> playSnippet(double durationInSeconds) async {
    try {
      debugPrint('▶️ Playing snippet for ${durationInSeconds}s');

      // Cancel any existing timer
      _stopTimer?.cancel();

      if (_currentUrl == null) {
        throw StateError('Audio must be loaded before playing a snippet.');
      }

      final clipEnd = Duration(milliseconds: (durationInSeconds * 1000).round());

      await _player.setAudioSource(
        ClippingAudioSource(
          start: Duration.zero,
          end: clipEnd,
          child: AudioSource.uri(Uri.parse(_currentUrl!)),
        ),
        initialPosition: Duration.zero,
        preload: true,
      );

      _isPlaying = true;
      await _player.play();

      debugPrint('✅ Playback started');

      await _player.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      );
      _isPlaying = false;
      debugPrint('⏹️ Playback stopped after ${durationInSeconds}s');
    } catch (e) {
      _isPlaying = false;
      _stopTimer?.cancel();
      debugPrint('❌ Failed to play snippet: $e');
      throw Exception('Failed to play snippet: $e');
    }
  }

  /// Stop playback
  Future<void> stop({bool cancelTimer = true}) async {
    if (cancelTimer) {
      _stopTimer?.cancel();
    }
    await _player.stop();
    await _player.seek(Duration.zero);
    _isPlaying = false;
  }

  /// Pause playback
  Future<void> pause() async {
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
        duration = 0.1;
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
        duration = 0.1;
    }
    await playSnippet(duration);
  }
}
