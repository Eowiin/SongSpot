import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/config/api_config.dart';

void main() {
  group('ApiConfig websocket origin', () {
    test('uses SERVER_URL as the websocket origin when available', () {
      dotenv.loadFromString(
        envString: '''
SERVER_URL=https://songspot.eowinstudio.com
API_BASE_URL=https://songspot.eowinstudio.com/api
WS_BASE_URL=wss://songspot.eowinstudio.com
''',
      );

      expect(
        ApiConfig.webSocketHeaders['Origin'],
        'https://songspot.eowinstudio.com',
      );
    });

    test('falls back to converting WS_BASE_URL to http origin', () {
      dotenv.loadFromString(
        envString: '''
API_BASE_URL=http://192.168.10.109:8000/api
WS_BASE_URL=ws://192.168.10.109:8000
''',
      );

      expect(
        ApiConfig.webSocketHeaders['Origin'],
        'http://192.168.10.109:8000',
      );
    });
  });
}
