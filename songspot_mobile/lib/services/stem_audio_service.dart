import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

class StemAudioService {
  final List<AudioPlayer> _players = [];
  List<String> _preparedUrls = const [];
  bool _isPlaying = false;
  bool _isInitialized = false;

  bool get isPlaying => _isPlaying;

  Future<void> _initializeSession() async {
    if (_isInitialized) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _isInitialized = true;
  }

  Future<void> prepareStems(List<String> urls) async {
    await _initializeSession();
    if (_isPreparedFor(urls)) {
      return;
    }

    await stop();

    final players = <AudioPlayer>[];
    for (var i = 0; i < urls.length; i += 1) {
      final player = AudioPlayer();
      players.add(player);
    }

    try {
      await Future.wait([
        for (var i = 0; i < urls.length; i += 1) players[i].setUrl(urls[i]),
      ]);
      _players
        ..clear()
        ..addAll(players);
      _preparedUrls = List<String>.from(urls);
    } catch (error) {
      for (final player in players) {
        await player.dispose();
      }
      rethrow;
    }
  }

  Future<void> playStems(List<String> urls) async {
    await prepareStems(urls);
    if (_players.isEmpty) return;

    await Future.wait(
      _players.map((player) async {
        await player.pause();
        await player.seek(Duration.zero);
      }),
    );

    _isPlaying = true;
    try {
      await Future.wait([for (final player in _players) player.play()]);
    } finally {
      _isPlaying = false;
    }
  }

  Future<void> stop() async {
    for (final player in _players) {
      await player.stop();
      await player.dispose();
    }
    _players.clear();
    _preparedUrls = const [];
    _isPlaying = false;
  }

  Future<void> dispose() async {
    await stop();
  }

  bool _isPreparedFor(List<String> urls) {
    if (_players.length != urls.length || _preparedUrls.length != urls.length) {
      return false;
    }

    for (var i = 0; i < urls.length; i += 1) {
      if (_preparedUrls[i] != urls[i]) {
        return false;
      }
    }

    return true;
  }
}
