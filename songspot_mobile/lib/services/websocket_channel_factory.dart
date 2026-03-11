import 'package:web_socket_channel/web_socket_channel.dart';

import 'websocket_channel_factory_stub.dart'
    if (dart.library.io) 'websocket_channel_factory_io.dart';

WebSocketChannel createWebSocketChannel(Uri uri) =>
    createPlatformWebSocketChannel(uri);
