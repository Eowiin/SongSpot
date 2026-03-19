import 'package:equatable/equatable.dart';
import 'user.dart';
import 'track.dart';

class DailySong extends Equatable {
  final String id;
  final Track track;
  final String mode;
  final String? genreKey;
  final String? genreName;
  final String date;
  final DateTime createdAt;

  const DailySong({
    required this.id,
    required this.track,
    this.mode = 'mix',
    this.genreKey,
    this.genreName,
    required this.date,
    required this.createdAt,
  });

  factory DailySong.fromJson(Map<String, dynamic> json) {
    return DailySong(
      id: json['id'].toString(),
      track: Track.fromJson(json['track'] as Map<String, dynamic>),
      mode: json['mode'] as String? ?? 'mix',
      genreKey: json['genre_key'] as String?,
      genreName: json['genre_name'] as String?,
      date: json['date'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [
    id,
    track,
    mode,
    genreKey,
    genreName,
    date,
    createdAt,
  ];
}

class GameSession extends Equatable {
  final String id;
  final User user;
  final DailySong dailySong;
  final int currentSnippet;
  final int guessesMade;
  final int retriesUsed;
  final int retryCredits;
  final bool awaitingRetryUnlock;
  final bool retryAvailable;
  final String? nextRetryRequirement;
  final int? retryCostCoins;
  final bool correctGuess;
  final int? pointsEarned;
  final DateTime? completedAt;
  final DateTime createdAt;
  final List<String> hintsUsed;

  const GameSession({
    required this.id,
    required this.user,
    required this.dailySong,
    required this.currentSnippet,
    required this.guessesMade,
    this.retriesUsed = 0,
    this.retryCredits = 0,
    this.awaitingRetryUnlock = false,
    this.retryAvailable = false,
    this.nextRetryRequirement,
    this.retryCostCoins,
    required this.correctGuess,
    this.pointsEarned,
    this.completedAt,
    required this.createdAt,
    this.hintsUsed = const [],
  });

  factory GameSession.fromJson(Map<String, dynamic> json) {
    return GameSession(
      id: json['id'].toString(),
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      dailySong: DailySong.fromJson(json['daily_song'] as Map<String, dynamic>),
      currentSnippet: json['current_snippet'] as int,
      guessesMade: json['guesses_made'] as int,
      retriesUsed: json['retries_used'] as int? ?? 0,
      retryCredits: json['retry_credits'] as int? ?? 0,
      awaitingRetryUnlock: json['awaiting_retry_unlock'] as bool? ?? false,
      retryAvailable: json['retry_available'] as bool? ?? false,
      nextRetryRequirement: json['next_retry_requirement'] as String?,
      retryCostCoins: json['retry_cost_coins'] as int?,
      correctGuess: json['correct_guess'] as bool,
      pointsEarned: json['points_earned'] as int?,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      hintsUsed: List.unmodifiable(
        List<String>.from(json['hints_used'] as List? ?? const []),
      ),
    );
  }

  GameSession copyWith({
    String? id,
    User? user,
    DailySong? dailySong,
    int? currentSnippet,
    int? guessesMade,
    int? retriesUsed,
    int? retryCredits,
    bool? awaitingRetryUnlock,
    bool? retryAvailable,
    String? nextRetryRequirement,
    bool clearNextRetryRequirement = false,
    int? retryCostCoins,
    bool? correctGuess,
    int? pointsEarned,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? createdAt,
    List<String>? hintsUsed,
  }) {
    return GameSession(
      id: id ?? this.id,
      user: user ?? this.user,
      dailySong: dailySong ?? this.dailySong,
      currentSnippet: currentSnippet ?? this.currentSnippet,
      guessesMade: guessesMade ?? this.guessesMade,
      retriesUsed: retriesUsed ?? this.retriesUsed,
      retryCredits: retryCredits ?? this.retryCredits,
      awaitingRetryUnlock: awaitingRetryUnlock ?? this.awaitingRetryUnlock,
      retryAvailable: retryAvailable ?? this.retryAvailable,
      nextRetryRequirement: clearNextRetryRequirement
          ? null
          : (nextRetryRequirement ?? this.nextRetryRequirement),
      retryCostCoins: retryCostCoins ?? this.retryCostCoins,
      correctGuess: correctGuess ?? this.correctGuess,
      pointsEarned: pointsEarned ?? this.pointsEarned,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      createdAt: createdAt ?? this.createdAt,
      hintsUsed: List.unmodifiable(hintsUsed ?? this.hintsUsed),
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
    return 7 -
        currentSnippet; // 6 points for snippet 1, down to 1 for snippet 6
  }

  @override
  List<Object?> get props => [
    id,
    user,
    dailySong,
    currentSnippet,
    guessesMade,
    retriesUsed,
    retryCredits,
    awaitingRetryUnlock,
    retryAvailable,
    nextRetryRequirement,
    retryCostCoins,
    correctGuess,
    pointsEarned,
    completedAt,
    createdAt,
    hintsUsed,
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
