import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

class StemAudioService {
  final List<AudioPlayer> _players = [];
  bool _isPlaying = false;
  bool _isInitialized = false;

  bool get isPlaying => _isPlaying;

  Future<void> _initializeSession() async {
    if (_isInitialized) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _isInitialized = true;
  }

  Future<void> playStems(List<String> urls) async {
    await _initializeSession();
    await stop();
    _players.clear();

    for (final url in urls) {
      final player = AudioPlayer();
      await player.setUrl(url);
      _players.add(player);
    }

    _isPlaying = true;
    await Future.wait(_players.map((player) => player.play()));
  }

  Future<void> stop() async {
    for (final player in _players) {
      await player.stop();
      await player.dispose();
    }
    _players.clear();
    _isPlaying = false;
  }

  Future<void> dispose() async {
    await stop();
  }
}
