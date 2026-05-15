import 'package:equatable/equatable.dart';
import 'playlist.dart';
import 'user.dart';

class Stem extends Equatable {
  final String type;
  final String url;

  const Stem({required this.type, required this.url});

  factory Stem.fromJson(Map<String, dynamic> json) {
    return Stem(type: json['type'] as String, url: json['url'] as String);
  }

  @override
  List<Object?> get props => [type, url];
}

class PackBundleSession extends Equatable {
  final String id;
  final int currentStage;
  final int retriesUsed;
  final int retryCredits;
  final bool awaitingRetryUnlock;
  final bool retryAvailable;
  final String? nextRetryRequirement;
  final int? retryCostCoins;
  final int pointsEarned;
  final DateTime? completedAt;
  final DateTime createdAt;
  final PlaylistTrack? packTrack;
  final String date;
  final List<String> hintsUsed;

  const PackBundleSession({
    required this.id,
    required this.currentStage,
    this.retriesUsed = 0,
    this.retryCredits = 0,
    this.awaitingRetryUnlock = false,
    this.retryAvailable = false,
    this.nextRetryRequirement,
    this.retryCostCoins,
    required this.pointsEarned,
    this.completedAt,
    required this.createdAt,
    required this.packTrack,
    required this.date,
    this.hintsUsed = const [],
  });

  factory PackBundleSession.fromJson(Map<String, dynamic> json) {
    return PackBundleSession(
      id: json['id'].toString(),
      currentStage: json['current_stage'] as int? ?? 1,
      retriesUsed: json['retries_used'] as int? ?? 0,
      retryCredits: json['retry_credits'] as int? ?? 0,
      awaitingRetryUnlock: json['awaiting_retry_unlock'] as bool? ?? false,
      retryAvailable: json['retry_available'] as bool? ?? false,
      nextRetryRequirement: json['next_retry_requirement'] as String?,
      retryCostCoins: json['retry_cost_coins'] as int?,
      pointsEarned: json['points_earned'] as int? ?? 0,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      packTrack: json['pack_track'] != null
          ? PlaylistTrack.fromJson(json['pack_track'] as Map<String, dynamic>)
          : null,
      date: json['date'] as String? ?? '',
      hintsUsed: List<String>.from(json['hints_used'] as List? ?? []),
    );
  }

  PackBundleSession copyWith({
    String? id,
    int? currentStage,
    int? retriesUsed,
    int? retryCredits,
    bool? awaitingRetryUnlock,
    bool? retryAvailable,
    String? nextRetryRequirement,
    bool clearNextRetryRequirement = false,
    int? retryCostCoins,
    int? pointsEarned,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? createdAt,
    PlaylistTrack? packTrack,
    String? date,
    List<String>? hintsUsed,
  }) {
    return PackBundleSession(
      id: id ?? this.id,
      currentStage: currentStage ?? this.currentStage,
      retriesUsed: retriesUsed ?? this.retriesUsed,
      retryCredits: retryCredits ?? this.retryCredits,
      awaitingRetryUnlock: awaitingRetryUnlock ?? this.awaitingRetryUnlock,
      retryAvailable: retryAvailable ?? this.retryAvailable,
      nextRetryRequirement: clearNextRetryRequirement
          ? null
          : (nextRetryRequirement ?? this.nextRetryRequirement),
      retryCostCoins: retryCostCoins ?? this.retryCostCoins,
      pointsEarned: pointsEarned ?? this.pointsEarned,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      createdAt: createdAt ?? this.createdAt,
      packTrack: packTrack ?? this.packTrack,
      date: date ?? this.date,
      hintsUsed: hintsUsed ?? this.hintsUsed,
    );
  }

  bool get isCompleted => completedAt != null;

  @override
  List<Object?> get props => [
    id,
    currentStage,
    retriesUsed,
    retryCredits,
    awaitingRetryUnlock,
    retryAvailable,
    nextRetryRequirement,
    retryCostCoins,
    pointsEarned,
    completedAt,
    createdAt,
    packTrack,
    date,
    hintsUsed,
  ];
}

class PackBundleLeaderboardEntry extends Equatable {
  final User user;
  final int pointsEarned;
  final int stageNumber;
  final DateTime completedAt;

  const PackBundleLeaderboardEntry({
    required this.user,
    required this.pointsEarned,
    required this.stageNumber,
    required this.completedAt,
  });

  factory PackBundleLeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return PackBundleLeaderboardEntry(
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      pointsEarned: json['points_earned'] as int,
      stageNumber: json['stage_number'] as int,
      completedAt: DateTime.parse(json['completed_at'] as String),
    );
  }

  @override
  List<Object?> get props => [user, pointsEarned, stageNumber, completedAt];
}
