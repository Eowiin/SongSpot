import 'package:equatable/equatable.dart';

class Track extends Equatable {
  final String id;
  final String title;
  final String artist;
  final String? previewUrl;
  final String? coverUrl;
  final int? releaseYear;
  final String? genre;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.previewUrl,
    this.coverUrl,
    this.releaseYear,
    this.genre,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'].toString(),
      title: json['title'] as String,
      artist: json['artist'] as String,
      previewUrl: json['preview_url'] as String?,
      coverUrl: json['cover_url'] as String?,
      releaseYear: json['release_year'] as int?,
      genre: json['genre'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, title, artist, previewUrl, coverUrl, releaseYear, genre];
}
