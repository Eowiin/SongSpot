import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/models/track.dart';
import 'package:songspot_mobile/models/category.dart';
import 'package:songspot_mobile/models/game_score.dart';

Map<String, dynamic> _json(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;

void main() {
  group('Track', () {
    test('fromJson parses all fields correctly', () {
      final track = Track.fromJson({
        'id': 'abc-123',
        'title': 'Blinding Lights',
        'artist': 'The Weeknd',
        'preview_url': 'https://cdn.example.com/preview.mp3',
        'cover_url': 'https://cdn.example.com/cover.jpg',
        'release_year': 2019,
        'genre': 'pop',
      });
      expect(track.id, 'abc-123');
      expect(track.title, 'Blinding Lights');
      expect(track.artist, 'The Weeknd');
      expect(track.previewUrl, 'https://cdn.example.com/preview.mp3');
      expect(track.coverUrl, 'https://cdn.example.com/cover.jpg');
      expect(track.releaseYear, 2019);
      expect(track.genre, 'pop');
    });

    test('fromJson handles null optional fields', () {
      final track = Track.fromJson({
        'id': '1',
        'title': 'Bare Track',
        'artist': 'Artist',
        'preview_url': null,
        'cover_url': null,
        'release_year': null,
        'genre': null,
      });
      expect(track.previewUrl, isNull);
      expect(track.coverUrl, isNull);
      expect(track.releaseYear, isNull);
      expect(track.genre, isNull);
    });

    test('equality is based on all fields', () {
      final t1 = Track.fromJson({'id': '1', 'title': 'Song', 'artist': 'A'});
      final t2 = Track.fromJson({'id': '1', 'title': 'Song', 'artist': 'A'});
      expect(t1, equals(t2));
    });

    test('different ids are not equal', () {
      final t1 = Track.fromJson({'id': '1', 'title': 'Song', 'artist': 'A'});
      final t2 = Track.fromJson({'id': '2', 'title': 'Song', 'artist': 'A'});
      expect(t1, isNot(equals(t2)));
    });

    test('a round in play parses without the answer', () {
      // What /next-song/ returns now: audio and a token, no title or artist.
      // Parsing this used to throw, because both were required.
      final track = Track.fromJson({
        'id': 'abc-123',
        'preview_url': 'https://cdn.example.com/preview.mp3',
        'round_token': 'signed-token',
      });
      expect(track.title, isEmpty);
      expect(track.artist, isEmpty);
      expect(track.isRevealed, isFalse);
      expect(track.roundToken, 'signed-token');
    });

    test('revealedWith fills in the answer from the guess response', () {
      final round = Track.fromJson({
        'id': 'abc-123',
        'preview_url': 'https://cdn.example.com/preview.mp3',
        'round_token': 'signed-token',
      });
      final revealed = round.revealedWith({
        'id': 'abc-123',
        'title': 'Blinding Lights',
        'artist': 'The Weeknd',
        'cover_url': 'https://cdn.example.com/cover.jpg',
        'release_year': 2019,
        'genre': 'pop',
      });
      expect(revealed.isRevealed, isTrue);
      expect(revealed.title, 'Blinding Lights');
      expect(revealed.artist, 'The Weeknd');
      // The audio already loaded for this round has to survive the reveal.
      expect(revealed.previewUrl, 'https://cdn.example.com/preview.mp3');
      expect(revealed.roundToken, 'signed-token');
    });

    test('copyWith keeps the round token when the preview URL is refreshed', () {
      // Preview URLs expire mid-round. Losing the token here would leave the
      // guess unjudgeable.
      final round = Track.fromJson({
        'id': 'abc-123',
        'preview_url': 'https://cdn.example.com/old.mp3',
        'round_token': 'signed-token',
      });
      final refreshed = round.copyWith(previewUrl: 'https://cdn.example.com/new.mp3');
      expect(refreshed.previewUrl, 'https://cdn.example.com/new.mp3');
      expect(refreshed.roundToken, 'signed-token');
    });

    test('pool_size is carried through for artist sessions', () {
      final track = Track.fromJson({
        'id': '1',
        'preview_url': 'https://cdn.example.com/p.mp3',
        'pool_size': 4,
      });
      expect(track.poolSize, 4);
    });
  });

  group('Category', () {
    test('fromJson parses all fields correctly', () {
      final category = Category.fromJson({
        'id': 'pop',
        'name': 'Pop',
        'description': 'Pop music',
        'icon_url': 'https://cdn.example.com/icon.png',
        'category': 'pop',
        'track_count': 250,
      });
      expect(category.id, 'pop');
      expect(category.name, 'Pop');
      expect(category.description, 'Pop music');
      expect(category.iconUrl, 'https://cdn.example.com/icon.png');
      expect(category.category, 'pop');
      expect(category.trackCount, 250);
    });

    test('fromJson handles missing description and icon_url', () {
      final category = Category.fromJson({
        'id': 'rock',
        'name': 'Rock',
        'track_count': 120,
      });
      expect(category.description, '');
      expect(category.iconUrl, isNull);
      expect(category.trackCount, 120);
    });

    test('fromJson defaults track_count to 0 when missing', () {
      final category = Category.fromJson({'id': 'x', 'name': 'X'});
      expect(category.trackCount, 0);
    });
  });

  group('GameScore', () {
    test('fromJson parses all fields correctly', () {
      final score = GameScore.fromJson({
        'id': 'score-1',
        'category': 'pop',
        'category_name': 'Pop',
        'artist_filter': 'Drake',
        'songs_played': 10,
        'songs_correct': 7,
        'best_streak': 5,
        'total_score': 200,
        'played_at': '2024-01-15T12:00:00Z',
        'user': {'username': 'ethan'},
      });
      expect(score.id, 'score-1');
      expect(score.categoryId, 'pop');
      expect(score.categoryName, 'Pop');
      expect(score.artistFilter, 'Drake');
      expect(score.songsPlayed, 10);
      expect(score.songsCorrect, 7);
      expect(score.bestStreak, 5);
      expect(score.totalScore, 200);
      expect(score.username, 'ethan');
    });

    test('fromJson handles null optional fields', () {
      final score = GameScore.fromJson({
        'id': 'score-2',
        'category': null,
        'songs_played': 5,
        'songs_correct': 3,
        'best_streak': 2,
        'total_score': 60,
        'played_at': '2024-01-15T12:00:00Z',
      });
      expect(score.categoryId, isNull);
      expect(score.categoryName, isNull);
      expect(score.artistFilter, '');
      expect(score.username, isNull);
    });

    test('accuracy computed correctly', () {
      final score = GameScore.fromJson({
        'id': 's',
        'songs_played': 10,
        'songs_correct': 7,
        'best_streak': 0,
        'total_score': 0,
        'played_at': '2024-01-01T00:00:00Z',
      });
      expect(score.accuracy, closeTo(70.0, 0.01));
    });

    test('accuracy is 0 when no songs played', () {
      final score = GameScore.fromJson({
        'id': 's',
        'songs_played': 0,
        'songs_correct': 0,
        'best_streak': 0,
        'total_score': 0,
        'played_at': '2024-01-01T00:00:00Z',
      });
      expect(score.accuracy, 0.0);
    });
  });

  group('UserBest', () {
    test('empty is all zeros with no categories', () {
      final best = UserBest.empty;
      expect(best.bestScoreOverall, 0);
      expect(best.bestStreakOverall, 0);
      expect(best.totalSongsPlayed, 0);
      expect(best.totalSongsCorrect, 0);
      expect(best.perCategory, isEmpty);
    });

    test('fromJson parses all fields correctly', () {
      final best = UserBest.fromJson(_json('''
        {
          "best_score_overall": 500,
          "best_streak_overall": 12,
          "total_songs_played": 80,
          "total_songs_correct": 60,
          "per_category": {
            "pop": {"best_score": 200, "best_streak": 8, "songs_played": 30},
            "rock": {"best_score": 100, "best_streak": 4, "songs_played": 15}
          }
        }
      '''));
      expect(best.bestScoreOverall, 500);
      expect(best.bestStreakOverall, 12);
      expect(best.totalSongsPlayed, 80);
      expect(best.totalSongsCorrect, 60);
      expect(best.perCategory, isNotEmpty);
      expect(best.perCategory.length, 2);
      expect(best.perCategory['pop']?.bestScore, 200);
      expect(best.perCategory['rock']?.bestStreak, 4);
    });

    test('fromJson handles empty per_category', () {
      final best = UserBest.fromJson(_json(
        '{"best_score_overall":0,"best_streak_overall":0,"total_songs_played":0,"total_songs_correct":0,"per_category":{}}',
      ));
      expect(best.perCategory, isEmpty);
    });
  });

  group('CategoryBest', () {
    test('fromJson parses all fields correctly', () {
      final cb = CategoryBest.fromJson({
        'best_score': 150,
        'best_streak': 6,
        'songs_played': 25,
      });
      expect(cb.bestScore, 150);
      expect(cb.bestStreak, 6);
      expect(cb.songsPlayed, 25);
    });

    test('fromJson defaults to 0 when fields missing', () {
      final cb = CategoryBest.fromJson({});
      expect(cb.bestScore, 0);
      expect(cb.bestStreak, 0);
      expect(cb.songsPlayed, 0);
    });
  });
}
