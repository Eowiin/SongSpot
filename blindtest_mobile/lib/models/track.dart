import 'package:equatable/equatable.dart';

class Track extends Equatable {
  final String id;
  final String title;
  final String artist;
  final String previewUrl;
  final DateTime createdAt;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.previewUrl,
    required this.createdAt,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'].toString(),
      title: json['title'] as String,
      artist: json['artist'] as String,
      previewUrl: json['preview_url'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'preview_url': previewUrl,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, title, artist, previewUrl, createdAt];
}
