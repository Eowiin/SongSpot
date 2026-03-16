import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api_config.dart';
import '../models/message.dart';
import '../models/user.dart';
import 'storage_service.dart';
import 'websocket_channel_factory.dart';

/// Events that can be emitted by the WebSocket service
enum WebSocketEventType {
  connected,
  disconnected,
  message,
  leaderboardUpdated,
  roomModeUpdated,
  userJoined,
  userLeft,
  typing,
  stemsReady,
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
  StreamSubscription? _streamSubscription;
  String? _currentRoomId;
  String _currentMode = 'mix';
  bool _isConnected = false;
  bool _intentionalDisconnect = false;
  Timer? _reconnectTimer;
  Timer? _reconnectResetTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  // Stream controller for broadcasting events
  final _eventController = StreamController<WebSocketEvent>.broadcast();
  Stream<WebSocketEvent> get events => _eventController.stream;

  bool get isConnected => _isConnected;
  String? get currentRoomId => _currentRoomId;

  /// Connect to a room's chat WebSocket
  Future<bool> connect(String roomId, {String mode = 'mix'}) async {
    // Disconnect from any existing connection
    _intentionalDisconnect = true;
    await disconnect();
    _intentionalDisconnect = false;

    try {
      final token = await _storageService.getAccessToken();
      if (token == null) {
        _eventController.add(
          WebSocketEvent(WebSocketEventType.error, 'Not authenticated'),
        );
        return false;
      }

      final wsUri = ApiConfig.roomChatWebSocketUri(roomId, token, mode: mode);
      final headers = ApiConfig.webSocketHeaders;

      _currentRoomId = roomId;
      _currentMode = mode;
      _channel = createWebSocketChannel(wsUri, headers: headers);

      // Wait for the HTTP upgrade to complete before reporting success.
      await _channel!.ready;

      // Listen to messages
      _streamSubscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      _isConnected = true;
      _eventController.add(WebSocketEvent(WebSocketEventType.connected));

      // Only reset reconnect attempts after connection is stable for 10s
      _reconnectResetTimer?.cancel();
      _reconnectResetTimer = Timer(const Duration(seconds: 10), () {
        _reconnectAttempts = 0;
      });

      return true;
    } catch (e) {
      debugPrint('WebSocket connection error: $e');
      _isConnected = false;
      await _streamSubscription?.cancel();
      _streamSubscription = null;

      if (_channel != null) {
        await _channel!.sink.close();
        _channel = null;
      }

      _eventController.add(
        WebSocketEvent(WebSocketEventType.error, 'Connection failed: $e'),
      );
      _scheduleReconnect();
      return false;
    }
  }

  /// Disconnect from the current WebSocket
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectResetTimer?.cancel();
    _reconnectResetTimer = null;

    if (_channel != null) {
      await _channel!.sink.close();
      _channel = null;
    }

    // Cancel subscription after closing so _onDone fires and emits the disconnected event
    await _streamSubscription?.cancel();
    _streamSubscription = null;

    _currentRoomId = null;
    _isConnected = false;
    debugPrint('WebSocket disconnected');
  }

  /// Send a chat message.
  /// Returns true when the payload was written to the socket sink.
  bool sendMessage(String message, {String? clientMessageId}) {
    if (!_isConnected || _channel == null) {
      debugPrint('Cannot send message: not connected');
      return false;
    }

    try {
      _channel!.sink.add(
        jsonEncode({
          'type': 'chat_message',
          'message': message,
          if (clientMessageId != null) 'client_message_id': clientMessageId,
        }),
      );
      return true;
    } catch (e) {
      debugPrint('WebSocket sendMessage failed: $e');
      _isConnected = false;
      _eventController.add(
        WebSocketEvent(WebSocketEventType.error, 'Send failed: $e'),
      );
      _scheduleReconnect();
      return false;
    }
  }

  /// Send typing indicator
  void sendTyping(bool isTyping) {
    if (!_isConnected || _channel == null) return;

    _channel!.sink.add(jsonEncode({'type': 'typing', 'is_typing': isTyping}));
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
            clientMessageId: json['client_message_id']?.toString(),
          );
          _eventController.add(
            WebSocketEvent(WebSocketEventType.message, message),
          );
          break;

        case 'leaderboard_updated':
          _eventController.add(
            WebSocketEvent(WebSocketEventType.leaderboardUpdated, {
              'room_id': json['room_id'] as String?,
              'user_id': json['user_id'] as String?,
              'mode': json['mode'] as String?,
            }),
          );
          break;

        case 'room_mode_updated':
          _eventController.add(
            WebSocketEvent(WebSocketEventType.roomModeUpdated, {
              'room_id': json['room_id'] as String?,
              'daily_modes': json['daily_modes'] as List<dynamic>? ?? const [],
              'activity_message': json['activity_message'] as String?,
              'actor_user_id': json['actor_user_id'] as String?,
            }),
          );
          break;

        case 'user_joined':
          final user = User.fromJson(json['user'] as Map<String, dynamic>);
          _eventController.add(
            WebSocketEvent(WebSocketEventType.userJoined, user),
          );
          break;

        case 'user_left':
          final user = User.fromJson(json['user'] as Map<String, dynamic>);
          _eventController.add(
            WebSocketEvent(WebSocketEventType.userLeft, user),
          );
          break;

        case 'typing':
          _eventController.add(
            WebSocketEvent(WebSocketEventType.typing, {
              'user': User.fromJson(json['user'] as Map<String, dynamic>),
              'is_typing': json['is_typing'] as bool,
            }),
          );
          break;

        case 'stems_ready':
          _eventController.add(
            WebSocketEvent(WebSocketEventType.stemsReady, {
              'pack_id': json['pack_id'] as String?,
              'pack_track_id': json['pack_track_id'] as String?,
            }),
          );
          break;

        case 'error':
          _eventController.add(
            WebSocketEvent(
              WebSocketEventType.error,
              json['message'] ?? 'Unknown error',
            ),
          );
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
    _eventController.add(
      WebSocketEvent(WebSocketEventType.error, error.toString()),
    );
    if (!_intentionalDisconnect) {
      _scheduleReconnect();
    }
  }

  void _onDone() {
    debugPrint('WebSocket connection closed');
    _isConnected = false;
    _reconnectResetTimer?.cancel();
    _reconnectResetTimer = null;
    _eventController.add(WebSocketEvent(WebSocketEventType.disconnected));
    if (!_intentionalDisconnect) {
      _scheduleReconnect();
    }
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
          await connect(_currentRoomId!, mode: _currentMode);
        }
      },
    );
  }

  /// Dispose of resources
  void dispose() {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectResetTimer?.cancel();
    _streamSubscription?.cancel();
    _channel?.sink.close();
    _eventController.close();
  }
}
