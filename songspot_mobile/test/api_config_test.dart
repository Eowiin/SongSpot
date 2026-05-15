import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/config/api_config.dart';

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: '', isOptional: true);
  });

  group('ApiConfig', () {
    test('base url falls back to localhost when no env var is set', () {
      expect(ApiConfig.baseUrl, isNotEmpty);
      expect(ApiConfig.baseUrl, contains('localhost'));
    });

    test('game endpoints are defined', () {
      expect(ApiConfig.categories, isNotEmpty);
      expect(ApiConfig.nextSong, isNotEmpty);
      expect(ApiConfig.submitScore, isNotEmpty);
      expect(ApiConfig.leaderboard, isNotEmpty);
      expect(ApiConfig.userStats, isNotEmpty);
    });

    test('auth endpoints are defined', () {
      expect(ApiConfig.authLogin, isNotEmpty);
      expect(ApiConfig.authRegister, isNotEmpty);
      expect(ApiConfig.authProfile, isNotEmpty);
    });
  });
}
