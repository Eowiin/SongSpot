import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../models/duel.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/websocket_service.dart';

enum DuelStatus {
  idle,
  queuing,
  matched,     // match found, about to connect to game WS
  loading,     // round_start received, waiting for audio / opponent to be ready
  playing,     // round in progress (controls enabled)
  roundReveal, // showing round result
  finished,    // match ended
  error,
}

class DuelProvider extends ChangeNotifier {
  final _api = ApiService();
  final _storage = StorageService();
  final _queueWs = WebSocketService();
  // Game WS retries aggressively — 20 attempts with exponential backoff up to
  // 30s each gives ~10 minutes of retrying before giving up.
  final _gameWs = WebSocketService(maxRetries: 20);

  DuelStatus _status = DuelStatus.idle;
  DuelStatus get status => _status;

  UserElo? _elo;
  UserElo? get elo => _elo;

  DuelOpponent? _opponent;
  DuelOpponent? get opponent => _opponent;

  DuelPlaylist? _playlist;
  DuelPlaylist? get playlist => _playlist;

  String? _matchId;
  String? get matchId => _matchId;

  // Round state
  int _currentRound = 0;
  int get currentRound => _currentRound;

  int _totalRounds = 5;
  int get totalRounds => _totalRounds;

  DuelTrack? _currentTrack;
  DuelTrack? get currentTrack => _currentTrack;

  int _snippetsUsed = 0;
  int get snippetsUsed => _snippetsUsed;

  bool _hasSubmitted = false;
  bool get hasSubmitted => _hasSubmitted;

  bool _opponentSubmitted = false;
  bool get opponentSubmitted => _opponentSubmitted;

  int _playerScore = 0;
  int get playerScore => _playerScore;

  int _opponentScore = 0;
  int get opponentScore => _opponentScore;

  DuelRoundResult? _lastRoundResult;
  DuelRoundResult? get lastRoundResult => _lastRoundResult;

  DuelMatchEnd? _matchEnd;
  DuelMatchEnd? get matchEnd => _matchEnd;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // True once local audio has buffered; false while still loading or between rounds.
  // Used to show "Waiting for opponent..." vs "Loading audio..." in the overlay.
  bool _localAudioReady = false;
  bool get localAudioReady => _localAudioReady;

  int _roundTimeRemaining = 0;
  int get roundTimeRemaining => _roundTimeRemaining;

  // Monotonically increasing counter — incremented on every round_start and on
  // reconnect to an active round. Used by the screen to detect when audio must
  // be reloaded (avoids the round-number-equality trap on reconnect).
  int _roundVersion = 0;
  int get roundVersion => _roundVersion;

  // When reconnecting to an already-running round the server won't send
  // round_begin again, so we skip the WS audio_ready send and jump straight
  // to playing once the audio has buffered locally.
  bool _skipAudioReadySignal = false;

  Timer? _roundTimer;

  StreamSubscription? _queueSub;
  StreamSubscription? _gameSub;

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> loadElo() async {
    try {
      final data = await _api.getDuelElo();
      _elo = UserElo.fromJson(data);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> joinQueue({String? playlistId}) async {
    _setStatus(DuelStatus.queuing);
    _reset();

    final token = await _storage.getAccessToken();
    if (token == null) {
      _setError('Not authenticated.');
      return;
    }

    final wsBase = ApiConfig.wsBaseUrl;
    final queuePath = '/ws/duel/queue/';
    final params = 'token=$token${playlistId != null ? '&playlist=$playlistId' : ''}';
    final uri = Uri.parse('$wsBase$queuePath?$params');

    _queueSub = _queueWs.messages.listen(_onQueueMessage);
    _queueWs.statusChanges.listen((s) {
      if (s == WsStatus.error && _status == DuelStatus.queuing) {
        _setError('Failed to connect to matchmaking server.');
      }
    });

    await _queueWs.connect(uri);
  }

  Future<void> leaveQueue() async {
    await _queueWs.disconnect();
    await _queueSub?.cancel();
    _queueSub = null;
    _setStatus(DuelStatus.idle);
  }

  /// Called by the game screen when the player wants to extend the snippet.
  void requestNextSnippet() {
    if (_hasSubmitted || _snippetsUsed >= 5) return;
    _snippetsUsed++;
    notifyListeners();
  }

  /// Called when the player selects a track from autocomplete and submits.
  void submitGuess(String trackId) {
    if (_hasSubmitted || _status != DuelStatus.playing) return;
    _hasSubmitted = true;
    notifyListeners();

    _gameWs.send({
      'type': 'submit_guess',
      'track_id': trackId,
      'snippets_used': _snippetsUsed,
    });
  }

  /// Called by the game screen once audio has finished buffering.
  void notifyAudioReady() {
    _localAudioReady = true;
    notifyListeners(); // update overlay text to "Waiting for opponent..."
    if (_skipAudioReadySignal) {
      _skipAudioReadySignal = false;
      _setStatus(DuelStatus.playing);
      return;
    }
    _gameWs.send({'type': 'audio_ready'});
  }

  Future<void> disconnect() async {
    _roundTimer?.cancel();
    _roundTimer = null;
    await _gameWs.disconnect();
    await _gameSub?.cancel();
    _gameSub = null;
    await leaveQueue();
  }

  // ── Queue WS events ────────────────────────────────────────────────────────

  void _onQueueMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'match_found':
        _handleMatchFound(msg);
    }
  }

  Future<void> _handleMatchFound(Map<String, dynamic> msg) async {
    _matchId = msg['match_id'] as String;
    _opponent = DuelOpponent.fromJson(msg['opponent'] as Map<String, dynamic>);
    final pl = msg['playlist'];
    _playlist = pl != null ? DuelPlaylist.fromJson(pl as Map<String, dynamic>) : null;

    _setStatus(DuelStatus.matched);

    // Disconnect matchmaking WS, connect to game WS
    await _queueWs.disconnect();
    await _queueSub?.cancel();

    final token = await _storage.getAccessToken();
    if (token == null) {
      _setError('Not authenticated.');
      return;
    }
    final uri = Uri.parse('${ApiConfig.wsBaseUrl}/ws/duel/$_matchId/?token=$token');
    _gameSub = _gameWs.messages.listen(_onGameMessage);
    _gameWs.statusChanges.listen((s) {
      final inGame = _status != DuelStatus.idle &&
          _status != DuelStatus.finished &&
          _status != DuelStatus.error;
      if (s == WsStatus.error && inGame) {
        _errorMessage = 'Connection lost. Reconnecting...';
        notifyListeners();
      } else if (s == WsStatus.disconnected && inGame) {
        // All retries exhausted — route to error so the user gets back to lobby.
        _setError('Connection lost. Please restart the match.');
      } else if (s == WsStatus.connected && _errorMessage != null) {
        _errorMessage = null;
        notifyListeners();
      }
    });
    await _gameWs.connect(uri);
  }

  // ── Game WS events ─────────────────────────────────────────────────────────

  void _onGameMessage(Map<String, dynamic> msg) {
    debugPrint('[DuelProvider] _onGameMessage type=${msg['type']}');
    switch (msg['type']) {
      case 'round_start':
        _handleRoundStart(msg);
      case 'round_begin':
        _handleRoundBegin(msg);
      case 'opponent_submitted':
        _opponentSubmitted = true;
        notifyListeners();
      case 'round_result':
        _handleRoundResult(msg);
      case 'match_end':
        _handleMatchEnd(msg);
      case 'opponent_disconnected':
        _errorMessage = 'Your opponent disconnected.';
        notifyListeners();
      case 'opponent_reconnected':
        _errorMessage = null;
        notifyListeners();
      case 'reconnect_state':
        _handleReconnectState(msg);
    }
  }

  void _handleRoundStart(Map<String, dynamic> msg) {
    debugPrint('[DuelProvider] _handleRoundStart raw track=${msg['track']}');
    _currentRound = (msg['round'] as num).toInt();
    _currentTrack = DuelTrack.fromRoundStart(msg['track'] as Map<String, dynamic>);
    debugPrint('[DuelProvider] _handleRoundStart → previewUrl=${_currentTrack?.previewUrl} id=${_currentTrack?.id}');
    _snippetsUsed = 1;
    _hasSubmitted = false;
    _opponentSubmitted = false;
    _lastRoundResult = null;
    _localAudioReady = false;
    _roundVersion++;
    _setStatus(DuelStatus.loading);
  }

  void _handleRoundBegin(Map<String, dynamic> msg) {
    _roundTimer?.cancel();
    final timeLimit = (msg['time_limit'] as num?)?.toInt() ?? 60;
    _roundTimeRemaining = timeLimit;
    _startRoundTimer();
    _setStatus(DuelStatus.playing);
  }

  void _startRoundTimer() {
    _roundTimer?.cancel();
    _roundTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_roundTimeRemaining <= 0) {
        t.cancel();
        _roundTimer = null;
        return;
      }
      _roundTimeRemaining--;
      notifyListeners();
    });
  }

  void _handleRoundResult(Map<String, dynamic> msg) {
    _roundTimer?.cancel();
    _roundTimer = null;
    _roundTimeRemaining = 0;
    _lastRoundResult = DuelRoundResult.fromJson(msg);
    _playerScore = _lastRoundResult!.playerScore;
    _opponentScore = _lastRoundResult!.opponentScore;
    _setStatus(DuelStatus.roundReveal);
  }

  void _handleReconnectState(Map<String, dynamic> msg) {
    _roundTimer?.cancel();
    _roundTimer = null;

    _currentRound = (msg['round'] as num).toInt();
    _totalRounds = (msg['total_rounds'] as num?)?.toInt() ?? _totalRounds;
    _currentTrack = DuelTrack.fromRoundStart(msg['track'] as Map<String, dynamic>);
    _snippetsUsed = 1;
    _hasSubmitted = false;
    _opponentSubmitted = false;
    _lastRoundResult = null;

    final scores = msg['scores'] as Map<String, dynamic>?;
    if (scores != null) {
      _playerScore = (scores['player'] as num?)?.toInt() ?? _playerScore;
      _opponentScore = (scores['opponent'] as num?)?.toInt() ?? _opponentScore;
    }

    final timeRemaining = (msg['time_remaining'] as num?)?.toInt() ?? 0;
    final roundActive = msg['round_active'] as bool? ?? false;

    if (roundActive && timeRemaining > 0) {
      // Increment version so the screen re-triggers audio load.
      // Set skip flag so notifyAudioReady() goes directly to playing instead
      // of sending audio_ready to server (server won't send round_begin again).
      _localAudioReady = false;
      _roundVersion++;
      _skipAudioReadySignal = true;
      _roundTimeRemaining = timeRemaining;
      _startRoundTimer();
      _setStatus(DuelStatus.loading);
    } else {
      // Round not active — wait for the next round_start from server.
      _roundTimeRemaining = 0;
      _setStatus(DuelStatus.matched);
    }
  }

  void _handleMatchEnd(Map<String, dynamic> msg) {
    _matchEnd = DuelMatchEnd.fromJson(msg);
    // Update ELO locally
    if (_elo != null) {
      _elo = UserElo(
        elo: _matchEnd!.newElo,
        wins: _matchEnd!.winner == 'player' ? _elo!.wins + 1 : _elo!.wins,
        losses: _matchEnd!.winner == 'opponent' ? _elo!.losses + 1 : _elo!.losses,
        draws: _matchEnd!.winner == 'draw' ? _elo!.draws + 1 : _elo!.draws,
        rank: _elo!.rank,
      );
    }
    _setStatus(DuelStatus.finished);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _reset() {
    _roundTimer?.cancel();
    _roundTimer = null;
    _roundTimeRemaining = 0;
    _matchId = null;
    _opponent = null;
    _playlist = null;
    _currentRound = 0;
    _totalRounds = 5;
    _currentTrack = null;
    _snippetsUsed = 0;
    _hasSubmitted = false;
    _opponentSubmitted = false;
    _playerScore = 0;
    _opponentScore = 0;
    _lastRoundResult = null;
    _matchEnd = null;
    _errorMessage = null;
    _roundVersion = 0;
    _skipAudioReadySignal = false;
    _localAudioReady = false;
  }

  void _setStatus(DuelStatus s) {
    debugPrint('[DuelProvider] status → $s');
    _status = s;
    notifyListeners();
  }

  void reset() {
    disconnect();
    _reset();
    _setStatus(DuelStatus.idle);
  }

  void _setError(String message) {
    _errorMessage = message;
    _status = DuelStatus.error;
    notifyListeners();
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    _gameSub?.cancel();
    _queueWs.dispose();
    _gameWs.dispose();
    super.dispose();
  }
}
