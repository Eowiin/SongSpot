import 'package:equatable/equatable.dart';

class GameScore extends Equatable {
  final String id;
  final String? categoryId;
  final String? categoryName;
  final String artistFilter;
  final int songsPlayed;
  final int songsCorrect;
  final int bestStreak;
  final int totalScore;
  final DateTime playedAt;
  final String? username;

  const GameScore({
    required this.id,
    this.categoryId,
    this.categoryName,
    this.artistFilter = '',
    required this.songsPlayed,
    required this.songsCorrect,
    required this.bestStreak,
    required this.totalScore,
    required this.playedAt,
    this.username,
  });

  factory GameScore.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return GameScore(
      id: json['id'].toString(),
      categoryId: json['category']?.toString(),
      categoryName: json['category_name'] as String?,
      artistFilter: json['artist_filter'] as String? ?? '',
      songsPlayed: json['songs_played'] as int? ?? 0,
      songsCorrect: json['songs_correct'] as int? ?? 0,
      bestStreak: json['best_streak'] as int? ?? 0,
      totalScore: json['total_score'] as int? ?? 0,
      playedAt: DateTime.parse(json['played_at'] as String),
      username: user?['username'] as String?,
    );
  }

  double get accuracy =>
      songsPlayed == 0 ? 0 : (songsCorrect / songsPlayed * 100);

  @override
  List<Object?> get props => [id, categoryId, totalScore, bestStreak, songsPlayed, playedAt];
}

class UserBest extends Equatable {
  final int bestScoreOverall;
  final int bestStreakOverall;
  final int totalSongsPlayed;
  final int totalSongsCorrect;
  final Map<String, CategoryBest> perCategory;

  const UserBest({
    required this.bestScoreOverall,
    required this.bestStreakOverall,
    required this.totalSongsPlayed,
    required this.totalSongsCorrect,
    required this.perCategory,
  });

  factory UserBest.fromJson(Map<String, dynamic> json) {
    final raw = json['per_category'] as Map<String, dynamic>? ?? {};
    final perCategory = raw.map(
      (k, v) => MapEntry(k, CategoryBest.fromJson(v as Map<String, dynamic>)),
    );
    return UserBest(
      bestScoreOverall: json['best_score_overall'] as int? ?? 0,
      bestStreakOverall: json['best_streak_overall'] as int? ?? 0,
      totalSongsPlayed: json['total_songs_played'] as int? ?? 0,
      totalSongsCorrect: json['total_songs_correct'] as int? ?? 0,
      perCategory: perCategory,
    );
  }

  static UserBest get empty => const UserBest(
    bestScoreOverall: 0,
    bestStreakOverall: 0,
    totalSongsPlayed: 0,
    totalSongsCorrect: 0,
    perCategory: {},
  );

  @override
  List<Object?> get props => [bestScoreOverall, bestStreakOverall, totalSongsPlayed];
}

class CategoryBest extends Equatable {
  final int bestScore;
  final int bestStreak;
  final int songsPlayed;

  const CategoryBest({
    required this.bestScore,
    required this.bestStreak,
    required this.songsPlayed,
  });

  factory CategoryBest.fromJson(Map<String, dynamic> json) {
    return CategoryBest(
      bestScore: json['best_score'] as int? ?? 0,
      bestStreak: json['best_streak'] as int? ?? 0,
      songsPlayed: json['songs_played'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [bestScore, bestStreak, songsPlayed];
}
