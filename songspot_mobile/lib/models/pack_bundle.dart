import 'package:equatable/equatable.dart';
import 'pack.dart';

class Stem extends Equatable {
  final String type;
  final String url;

  const Stem({required this.type, required this.url});

  factory Stem.fromJson(Map<String, dynamic> json) {
    return Stem(
      type: json['type'] as String,
      url: json['url'] as String,
    );
  }

  @override
  List<Object?> get props => [type, url];
}

class PackBundleSession extends Equatable {
  final String id;
  final int currentStage;
  final int pointsEarned;
  final DateTime? completedAt;
  final DateTime createdAt;
  final PackTrack? packTrack;
  final String date;

  const PackBundleSession({
    required this.id,
    required this.currentStage,
    required this.pointsEarned,
    this.completedAt,
    required this.createdAt,
    required this.packTrack,
    required this.date,
  });

  factory PackBundleSession.fromJson(Map<String, dynamic> json) {
    return PackBundleSession(
      id: json['id'].toString(),
      currentStage: json['current_stage'] as int? ?? 1,
      pointsEarned: json['points_earned'] as int? ?? 0,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      packTrack: json['pack_track'] != null
          ? PackTrack.fromJson(json['pack_track'] as Map<String, dynamic>)
          : null,
      date: json['date'] as String? ?? '',
    );
  }

  bool get isCompleted => completedAt != null;

  @override
  List<Object?> get props => [
        id,
        currentStage,
        pointsEarned,
        completedAt,
        createdAt,
        packTrack,
        date,
      ];
}
