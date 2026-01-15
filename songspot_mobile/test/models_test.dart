import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/models/user.dart';
import 'package:songspot_mobile/models/track.dart';
import 'package:songspot_mobile/models/room.dart';
import 'package:songspot_mobile/models/game_session.dart';
import 'package:songspot_mobile/models/message.dart';

void main() {
  group('User Model', () {
    test('fromJson creates User correctly', () {
      final json = {
        'id': '123e4567-e89b-12d3-a456-426614174000',
        'email': 'test@example.com',
        'username': 'testuser',
      };

      final user = User.fromJson(json);

      expect(user.id, '123e4567-e89b-12d3-a456-426614174000');
      expect(user.email, 'test@example.com');
      expect(user.username, 'testuser');
    });

    test('toJson serializes User correctly', () {
      const user = User(
        id: '123',
        email: 'test@example.com',
        username: 'testuser',
      );

      final json = user.toJson();

      expect(json['id'], '123');
      expect(json['email'], 'test@example.com');
      expect(json['username'], 'testuser');
    });

    test('User equality works with Equatable', () {
      const user1 = User(id: '1', email: 'a@b.com', username: 'user');
      const user2 = User(id: '1', email: 'a@b.com', username: 'user');
      const user3 = User(id: '2', email: 'a@b.com', username: 'user');

      expect(user1, equals(user2));
      expect(user1, isNot(equals(user3)));
    });
  });

  group('Track Model', () {
    test('fromJson creates Track correctly', () {
      final json = {
        'id': 'track-123',
        'title': 'Bohemian Rhapsody',
        'artist': 'Queen',
        'preview_url': 'https://example.com/preview.mp3',
        'cover_url': 'https://example.com/cover.jpg',
        'created_at': '2024-01-15T10:00:00Z',
      };

      final track = Track.fromJson(json);

      expect(track.id, 'track-123');
      expect(track.title, 'Bohemian Rhapsody');
      expect(track.artist, 'Queen');
      expect(track.previewUrl, 'https://example.com/preview.mp3');
      expect(track.coverUrl, 'https://example.com/cover.jpg');
    });

    test('fromJson handles null cover_url', () {
      final json = {
        'id': 'track-123',
        'title': 'Test Song',
        'artist': 'Test Artist',
        'preview_url': 'https://example.com/preview.mp3',
        'cover_url': null,
        'created_at': '2024-01-15T10:00:00Z',
      };

      final track = Track.fromJson(json);

      expect(track.coverUrl, isNull);
    });

    test('toJson serializes Track correctly', () {
      final track = Track(
        id: 'track-123',
        title: 'Test Song',
        artist: 'Test Artist',
        previewUrl: 'https://example.com/preview.mp3',
        coverUrl: 'https://example.com/cover.jpg',
        createdAt: DateTime.parse('2024-01-15T10:00:00Z'),
      );

      final json = track.toJson();

      expect(json['id'], 'track-123');
      expect(json['title'], 'Test Song');
      expect(json['artist'], 'Test Artist');
      expect(json['preview_url'], 'https://example.com/preview.mp3');
    });
  });

  group('Room Model', () {
    test('fromJson creates Room correctly', () {
      final json = {
        'id': 'room-123',
        'room_code': 'ABC123',
        'name': 'Test Room',
        'host_user': {
          'id': 'user-1',
          'email': 'host@example.com',
          'username': 'hostuser',
        },
        'users': [
          {
            'user': {
              'id': 'user-1',
              'email': 'host@example.com',
              'username': 'hostuser',
            },
            'joined_at': '2024-01-15T10:00:00Z',
          },
        ],
        'user_count': 1,
        'created_at': '2024-01-15T10:00:00Z',
      };

      final room = Room.fromJson(json);

      expect(room.id, 'room-123');
      expect(room.roomCode, 'ABC123');
      expect(room.name, 'Test Room');
      expect(room.hostUser.username, 'hostuser');
      expect(room.users.length, 1);
      expect(room.userCount, 1);
    });

    test('displayName returns name when set', () {
      final json = {
        'id': 'room-123',
        'room_code': 'ABC123',
        'name': 'My Cool Room',
        'host_user': {
          'id': 'user-1',
          'email': 'host@example.com',
          'username': 'hostuser',
        },
        'users': [],
        'user_count': 0,
        'created_at': '2024-01-15T10:00:00Z',
      };

      final room = Room.fromJson(json);

      expect(room.displayName, 'My Cool Room');
    });

    test('displayName returns "Room CODE" when name is null', () {
      final json = {
        'id': 'room-123',
        'room_code': 'ABC123',
        'name': null,
        'host_user': {
          'id': 'user-1',
          'email': 'host@example.com',
          'username': 'hostuser',
        },
        'users': [],
        'user_count': 0,
        'created_at': '2024-01-15T10:00:00Z',
      };

      final room = Room.fromJson(json);

      expect(room.displayName, 'Room ABC123');
    });

    test('isHost returns true for host user', () {
      final json = {
        'id': 'room-123',
        'room_code': 'ABC123',
        'name': null,
        'host_user': {
          'id': 'user-1',
          'email': 'host@example.com',
          'username': 'hostuser',
        },
        'users': [],
        'user_count': 0,
        'created_at': '2024-01-15T10:00:00Z',
      };

      final room = Room.fromJson(json);

      expect(room.isHost('user-1'), isTrue);
      expect(room.isHost('user-2'), isFalse);
    });
  });

  group('GameSession Model', () {
    test('fromJson creates GameSession correctly', () {
      final json = {
        'id': 'session-123',
        'user': {
          'id': 'user-1',
          'email': 'player@example.com',
          'username': 'player1',
        },
        'daily_song': {
          'id': 'daily-1',
          'track': {
            'id': 'track-1',
            'title': 'Test Song',
            'artist': 'Test Artist',
            'preview_url': 'https://example.com/preview.mp3',
            'cover_url': null,
            'created_at': '2024-01-15T10:00:00Z',
          },
          'date': '2024-01-15',
          'created_at': '2024-01-15T10:00:00Z',
        },
        'current_snippet': 1,
        'guesses_made': 0,
        'correct_guess': false,
        'points_earned': null,
        'completed_at': null,
        'created_at': '2024-01-15T10:00:00Z',
      };

      final session = GameSession.fromJson(json);

      expect(session.id, 'session-123');
      expect(session.currentSnippet, 1);
      expect(session.guessesMade, 0);
      expect(session.correctGuess, false);
    });

    test('isCompleted returns true when correctGuess is true', () {
      final session = GameSession(
        id: '1',
        user: const User(id: '1', email: 'a@b.com', username: 'user'),
        dailySong: DailySong(
          id: '1',
          track: Track(
            id: '1',
            title: 'Test',
            artist: 'Artist',
            previewUrl: 'url',
            createdAt: DateTime.now(),
          ),
          date: '2024-01-15',
          createdAt: DateTime.now(),
        ),
        currentSnippet: 1,
        guessesMade: 1,
        correctGuess: true,
        createdAt: DateTime.now(),
      );

      expect(session.isCompleted, isTrue);
    });

    test('isCompleted returns true when at snippet 6', () {
      final session = GameSession(
        id: '1',
        user: const User(id: '1', email: 'a@b.com', username: 'user'),
        dailySong: DailySong(
          id: '1',
          track: Track(
            id: '1',
            title: 'Test',
            artist: 'Artist',
            previewUrl: 'url',
            createdAt: DateTime.now(),
          ),
          date: '2024-01-15',
          createdAt: DateTime.now(),
        ),
        currentSnippet: 6,
        guessesMade: 5,
        correctGuess: false,
        createdAt: DateTime.now(),
      );

      expect(session.isCompleted, isTrue);
    });

    test('snippetDuration returns correct values', () {
      GameSession createWithSnippet(int snippet) => GameSession(
            id: '1',
            user: const User(id: '1', email: 'a@b.com', username: 'user'),
            dailySong: DailySong(
              id: '1',
              track: Track(
                id: '1',
                title: 'Test',
                artist: 'Artist',
                previewUrl: 'url',
                createdAt: DateTime.now(),
              ),
              date: '2024-01-15',
              createdAt: DateTime.now(),
            ),
            currentSnippet: snippet,
            guessesMade: 0,
            correctGuess: false,
            createdAt: DateTime.now(),
          );

      expect(createWithSnippet(1).snippetDuration, 0.1);
      expect(createWithSnippet(2).snippetDuration, 0.5);
      expect(createWithSnippet(3).snippetDuration, 2.0);
      expect(createWithSnippet(4).snippetDuration, 4.0);
      expect(createWithSnippet(5).snippetDuration, 8.0);
      expect(createWithSnippet(6).snippetDuration, 15.0);
    });

    test('possiblePoints returns correct values', () {
      GameSession createWithSnippet(int snippet) => GameSession(
            id: '1',
            user: const User(id: '1', email: 'a@b.com', username: 'user'),
            dailySong: DailySong(
              id: '1',
              track: Track(
                id: '1',
                title: 'Test',
                artist: 'Artist',
                previewUrl: 'url',
                createdAt: DateTime.now(),
              ),
              date: '2024-01-15',
              createdAt: DateTime.now(),
            ),
            currentSnippet: snippet,
            guessesMade: 0,
            correctGuess: false,
            createdAt: DateTime.now(),
          );

      expect(createWithSnippet(1).possiblePoints, 6);
      expect(createWithSnippet(2).possiblePoints, 5);
      expect(createWithSnippet(3).possiblePoints, 4);
      expect(createWithSnippet(4).possiblePoints, 3);
      expect(createWithSnippet(5).possiblePoints, 2);
      expect(createWithSnippet(6).possiblePoints, 1);
    });
  });

  group('LeaderboardEntry Model', () {
    test('fromJson creates LeaderboardEntry correctly', () {
      final json = {
        'user': {
          'id': 'user-1',
          'email': 'player@example.com',
          'username': 'player1',
        },
        'points_earned': 6,
        'snippet_number': 1,
        'completed_at': '2024-01-15T10:00:00Z',
      };

      final entry = LeaderboardEntry.fromJson(json);

      expect(entry.user.username, 'player1');
      expect(entry.pointsEarned, 6);
      expect(entry.snippetNumber, 1);
    });
  });

  group('Message Model', () {
    test('fromJson creates Message correctly', () {
      final json = {
        'id': 'msg-123',
        'user': {
          'id': 'user-1',
          'email': 'sender@example.com',
          'username': 'sender',
        },
        'message': 'Hello everyone!',
        'created_at': '2024-01-15T10:00:00Z',
      };

      final message = Message.fromJson(json);

      expect(message.id, 'msg-123');
      expect(message.user.username, 'sender');
      expect(message.message, 'Hello everyone!');
    });
  });
}
