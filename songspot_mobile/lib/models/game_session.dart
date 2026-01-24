import 'package:equatable/equatable.dart';
import 'user.dart';
import 'track.dart';

class DailySong extends Equatable {
  final String id;
  final Track track;
  final String date;
  final DateTime createdAt;

  const DailySong({
    required this.id,
    required this.track,
    required this.date,
    required this.createdAt,
  });

  factory DailySong.fromJson(Map<String, dynamic> json) {
    return DailySong(
      id: json['id'].toString(),
      track: Track.fromJson(json['track'] as Map<String, dynamic>),
      date: json['date'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id, track, date, createdAt];
}

class GameSession extends Equatable {
  final String id;
  final User user;
  final DailySong dailySong;
  final int currentSnippet;
  final int guessesMade;
  final bool correctGuess;
  final int? pointsEarned;
  final DateTime? completedAt;
  final DateTime createdAt;

  const GameSession({
    required this.id,
    required this.user,
    required this.dailySong,
    required this.currentSnippet,
    required this.guessesMade,
    required this.correctGuess,
    this.pointsEarned,
    this.completedAt,
    required this.createdAt,
  });

  factory GameSession.fromJson(Map<String, dynamic> json) {
    return GameSession(
      id: json['id'].toString(),
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      dailySong: DailySong.fromJson(json['daily_song'] as Map<String, dynamic>),
      currentSnippet: json['current_snippet'] as int,
      guessesMade: json['guesses_made'] as int,
      correctGuess: json['correct_guess'] as bool,
      pointsEarned: json['points_earned'] as int?,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isCompleted => completedAt != null || correctGuess;

  double get snippetDuration {
    switch (currentSnippet) {
      case 1:
        return 0.2;
      case 2:
        return 0.5;
      case 3:
        return 2.0;
      case 4:
        return 4.0;
      case 5:
        return 8.0;
      case 6:
        return 15.0;
      default:
        return 0.0;
    }
  }

  int get possiblePoints {
    return 7 - currentSnippet; // 6 points for snippet 1, down to 1 for snippet 6
  }

  @override
  List<Object?> get props => [
        id,
        user,
        dailySong,
        currentSnippet,
        guessesMade,
        correctGuess,
        pointsEarned,
        completedAt,
        createdAt,
      ];
}

class LeaderboardEntry extends Equatable {
  final User user;
  final int pointsEarned;
  final int snippetNumber;
  final DateTime completedAt;

  const LeaderboardEntry({
    required this.user,
    required this.pointsEarned,
    required this.snippetNumber,
    required this.completedAt,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      pointsEarned: json['points_earned'] as int,
      snippetNumber: json['snippet_number'] as int,
      completedAt: DateTime.parse(json['completed_at'] as String),
    );
  }

  @override
  List<Object?> get props => [user, pointsEarned, snippetNumber, completedAt];
}
