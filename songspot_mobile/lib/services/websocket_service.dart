import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api_config.dart';
import '../models/message.dart';
import '../models/user.dart';
import 'storage_service.dart';

/// Events that can be emitted by the WebSocket service
enum WebSocketEventType {
  connected,
  disconnected,
  message,
  userJoined,
  userLeft,
  typing,
  error,
}

class WebSocketEvent {
  final WebSocketEventType type;
  final dynamic data;

  WebSocketEvent(this.type, [this.data]);
}

/// Service for managing WebSocket connections for real-time chat
class WebSocketService {
  final StorageService _storageService = StorageService();

  WebSocketChannel? _channel;
  String? _currentRoomId;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  // Stream controller for broadcasting events
  final _eventController = StreamController<WebSocketEvent>.broadcast();
  Stream<WebSocketEvent> get events => _eventController.stream;

  bool get isConnected => _isConnected;
  String? get currentRoomId => _currentRoomId;

  /// Get WebSocket URL from API base URL
  String get _wsBaseUrl {
    final apiUrl = ApiConfig.baseUrl;
    // Convert http(s):// to ws(s)://
    if (apiUrl.startsWith('https://')) {
      return apiUrl.replaceFirst('https://', 'wss://').replaceAll('/api', '');
    } else {
      return apiUrl.replaceFirst('http://', 'ws://').replaceAll('/api', '');
    }
  }

  /// Connect to a room's chat WebSocket
  Future<bool> connect(String roomId) async {
    // Disconnect from any existing connection
    await disconnect();

    try {
      final token = await _storageService.getAccessToken();
      if (token == null) {
        _eventController.add(WebSocketEvent(
          WebSocketEventType.error,
          'Not authenticated',
        ));
        return false;
      }

      final wsUrl = '$_wsBaseUrl/ws/room/$roomId/chat/?token=$token';
      debugPrint('WebSocket connecting to: $wsUrl');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _currentRoomId = roomId;

      // Listen to messages
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      _isConnected = true;
      _reconnectAttempts = 0;
      _eventController.add(WebSocketEvent(WebSocketEventType.connected));

      return true;
    } catch (e) {
      debugPrint('WebSocket connection error: $e');
      _eventController.add(WebSocketEvent(
        WebSocketEventType.error,
        'Connection failed: $e',
      ));
      return false;
    }
  }

  /// Disconnect from the current WebSocket
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    if (_channel != null) {
      await _channel!.sink.close();
      _channel = null;
    }

    _currentRoomId = null;
    _isConnected = false;
  }

  /// Send a chat message
  void sendMessage(String message) {
    if (!_isConnected || _channel == null) {
      debugPrint('Cannot send message: not connected');
      return;
    }

    _channel!.sink.add(jsonEncode({
      'type': 'chat_message',
      'message': message,
    }));
  }

  /// Send typing indicator
  void sendTyping(bool isTyping) {
    if (!_isConnected || _channel == null) return;

    _channel!.sink.add(jsonEncode({
      'type': 'typing',
      'is_typing': isTyping,
    }));
  }

  void _onMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final type = json['type'] as String?;

      switch (type) {
        case 'chat_message':
          final message = Message(
            id: json['id'] as String,
            user: User.fromJson(json['user'] as Map<String, dynamic>),
            message: json['message'] as String,
            createdAt: DateTime.parse(json['created_at'] as String),
          );
          _eventController.add(WebSocketEvent(WebSocketEventType.message, message));
          break;

        case 'user_joined':
          final user = User.fromJson(json['user'] as Map<String, dynamic>);
          _eventController.add(WebSocketEvent(WebSocketEventType.userJoined, user));
          break;

        case 'user_left':
          final user = User.fromJson(json['user'] as Map<String, dynamic>);
          _eventController.add(WebSocketEvent(WebSocketEventType.userLeft, user));
          break;

        case 'typing':
          _eventController.add(WebSocketEvent(WebSocketEventType.typing, {
            'user': User.fromJson(json['user'] as Map<String, dynamic>),
            'is_typing': json['is_typing'] as bool,
          }));
          break;

        case 'error':
          _eventController.add(WebSocketEvent(
            WebSocketEventType.error,
            json['message'] ?? 'Unknown error',
          ));
          break;

        default:
          debugPrint('Unknown WebSocket message type: $type');
      }
    } catch (e) {
      debugPrint('Error parsing WebSocket message: $e');
    }
  }

  void _onError(dynamic error) {
    debugPrint('WebSocket error: $error');
    _isConnected = false;
    _eventController.add(WebSocketEvent(WebSocketEventType.error, error.toString()));
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('WebSocket connection closed');
    _isConnected = false;
    _eventController.add(WebSocketEvent(WebSocketEventType.disconnected));
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('Max reconnect attempts reached');
      return;
    }

    if (_currentRoomId == null) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      Duration(seconds: _reconnectAttempts * 2 + 1), // Exponential backoff
      () async {
        _reconnectAttempts++;
        debugPrint('Attempting reconnect #$_reconnectAttempts');
        if (_currentRoomId != null) {
          await connect(_currentRoomId!);
        }
      },
    );
  }

  /// Dispose of resources
  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _eventController.close();
  }
}
