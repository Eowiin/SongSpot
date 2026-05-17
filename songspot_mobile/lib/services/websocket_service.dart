import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'websocket_channel_factory.dart';

enum WsStatus { disconnected, connecting, connected, error }

class WebSocketService {
  static const int _maxRetries = 3;
  static const Duration _baseBackoff = Duration(seconds: 2);

  Uri? _uri;
  dynamic _channel;          // WebSocketChannel (avoid import coupling)
  StreamSubscription? _sub;

  WsStatus _status = WsStatus.disconnected;
  WsStatus get status => _status;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<WsStatus>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<WsStatus> get statusChanges => _statusController.stream;

  int _retries = 0;
  bool _intentionalClose = false;

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
    if (_intentionalClose || _retries >= _maxRetries) return;
    _retries++;
    final delay = _baseBackoff * _retries;
    debugPrint('[WS] Retrying in ${delay.inSeconds}s (attempt $_retries)');
    Future.delayed(delay, () {
      if (!_intentionalClose) _doConnect();
    });
  }

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
