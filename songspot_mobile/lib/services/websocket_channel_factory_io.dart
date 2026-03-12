import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel createPlatformWebSocketChannel(
  Uri uri, {
  Map<String, dynamic>? headers,
}) {
  return IOWebSocketChannel.connect(
    uri,
    headers: headers,
    connectTimeout: const Duration(seconds: 10),
    pingInterval: const Duration(seconds: 30),
  );
}
