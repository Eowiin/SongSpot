import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/config/api_config.dart';

void main() {
  group('ApiConfig', () {
    test('base url is not empty', () {
      expect(ApiConfig.baseUrl, isNotEmpty);
    });

    test('game endpoints are defined', () {
      expect(ApiConfig.categories, isNotEmpty);
      expect(ApiConfig.nextSong, isNotEmpty);
      expect(ApiConfig.submitScore, isNotEmpty);
      expect(ApiConfig.leaderboard, isNotEmpty);
      expect(ApiConfig.userStats, isNotEmpty);
    });
  });
}
