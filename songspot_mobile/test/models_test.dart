import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/models/track.dart';
import 'package:songspot_mobile/models/category.dart';
import 'package:songspot_mobile/models/game_score.dart';

void main() {
  group('Track', () {
    test('fromJson parses correctly', () {
      final track = Track.fromJson({
        'id': '1',
        'title': 'Test Song',
        'artist': 'Test Artist',
        'preview_url': 'https://example.com/preview.mp3',
        'cover_url': 'https://example.com/cover.jpg',
        'release_year': 2020,
        'genre': 'pop',
      });
      expect(track.id, '1');
      expect(track.title, 'Test Song');
      expect(track.artist, 'Test Artist');
      expect(track.releaseYear, 2020);
      expect(track.genre, 'pop');
    });
  });

  group('Category', () {
    test('fromJson parses correctly', () {
      final category = Category.fromJson({
        'id': 'cat1',
        'name': 'Pop',
        'description': 'Pop music',
        'category': 'pop',
        'track_count': 100,
      });
      expect(category.id, 'cat1');
      expect(category.name, 'Pop');
      expect(category.trackCount, 100);
    });
  });

  group('UserBest', () {
    test('empty is all zeros', () {
      final best = UserBest.empty;
      expect(best.bestScoreOverall, 0);
      expect(best.bestStreakOverall, 0);
      expect(best.totalSongsPlayed, 0);
    });
  });
}
