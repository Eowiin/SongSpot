import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'websocket_channel_factory.dart';

enum WsStatus { disconnected, connecting, connected, error }

class WebSocketService {
  /// Maximum number of automatic reconnect attempts before giving up.
  /// Pass a large value (e.g. 20) for connections that should retry aggressively.
  final int maxRetries;

  static const Duration _baseBackoff = Duration(seconds: 2);
  static const Duration _maxBackoff = Duration(seconds: 30);

  Uri? _uri;
  dynamic _channel;
  StreamSubscription? _sub;

  WsStatus _status = WsStatus.disconnected;
  WsStatus get status => _status;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<WsStatus>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<WsStatus> get statusChanges => _statusController.stream;

  int _retries = 0;
  bool _intentionalClose = false;

  WebSocketService({this.maxRetries = 3});

  Future<void> connect(Uri uri) async {
    _uri = uri;
    _intentionalClose = false;
    _retries = 0;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    _setStatus(WsStatus.connecting);
    try {
      _channel = createWebSocketChannel(_uri!);
      await _channel.ready;
      _setStatus(WsStatus.connected);
      _retries = 0;
      _sub = _channel.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[WS] Connect error: $e');
      _setStatus(WsStatus.error);
      _scheduleRetry();
    }
  }

  void send(Map<String, dynamic> data) {
    if (_status != WsStatus.connected) return;
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (e) {
      debugPrint('[WS] Send error: $e');
    }
  }

  Future<void> disconnect() async {
    _intentionalClose = true;
    await _cleanup();
    _setStatus(WsStatus.disconnected);
  }

  void _onData(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      _messageController.add(data);
    } catch (e) {
      debugPrint('[WS] Parse error: $e');
    }
  }

  void _onError(Object error) {
    debugPrint('[WS] Stream error: $error');
    _setStatus(WsStatus.error);
  }

  void _onDone() {
    if (_intentionalClose) return;
    debugPrint('[WS] Connection closed unexpectedly');
    _setStatus(WsStatus.error);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_intentionalClose) return;
    if (_retries >= maxRetries) {
      debugPrint('[WS] Max retries ($maxRetries) reached, giving up');
      _setStatus(WsStatus.disconnected);
      return;
    }
    _retries++;
    // Exponential backoff capped at _maxBackoff.
    final delay = _capDuration(_baseBackoff * (1 << (_retries - 1)));
    debugPrint('[WS] Retrying in ${delay.inSeconds}s (attempt $_retries/$maxRetries)');
    Future.delayed(delay, () {
      if (!_intentionalClose) _doConnect();
    });
  }

  Duration _capDuration(Duration d) =>
      d > _maxBackoff ? _maxBackoff : d;

  Future<void> _cleanup() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _setStatus(WsStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  void dispose() {
    _intentionalClose = true;
    _cleanup();
    _messageController.close();
    _statusController.close();
  }
}
