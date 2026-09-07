import 'package:equatable/equatable.dart';

/// A song, in one of two states.
///
/// While a round is being played the server withholds [title], [artist] and
/// [coverUrl] — they are the answer, and they used to travel alongside the
/// audio where anyone reading their own network traffic could see them. In
/// that state they are empty and [roundToken] identifies the round. Once the
/// guess is judged, `/game/guess/` returns the same song fully populated.
///
/// Tracks coming back from the search box are always complete: they are what
/// the player picks between, not what they are guessing at.
class Track extends Equatable {
  final String id;
  final String title;
  final String artist;
  final String? previewUrl;
  final String? coverUrl;
  final int? releaseYear;
  final String? genre;

  /// Opaque handle for the round this track was served for. Null for search
  /// results and for rounds served to older clients.
  final String? roundToken;

  /// How many tracks the chosen artist has available, when the session is
  /// scoped to one. Null for category and mixed play.
  final int? poolSize;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.previewUrl,
    this.coverUrl,
    this.releaseYear,
    this.genre,
    this.roundToken,
    this.poolSize,
  });

  /// True once the answer is known — after a guess, or on a search result.
  bool get isRevealed => title.isNotEmpty;

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'].toString(),
      // Absent while the round is in play; see the class docs.
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      previewUrl: json['preview_url'] as String?,
      coverUrl: json['cover_url'] as String?,
      releaseYear: json['release_year'] as int?,
      genre: json['genre'] as String?,
      roundToken: json['round_token'] as String?,
      poolSize: json['pool_size'] as int?,
    );
  }

  /// The same round, with the answer filled in from the guess response.
  Track revealedWith(Map<String, dynamic> answer) => Track(
        id: answer['id']?.toString() ?? id,
        title: answer['title'] as String? ?? title,
        artist: answer['artist'] as String? ?? artist,
        previewUrl: previewUrl,
        coverUrl: answer['cover_url'] as String? ?? coverUrl,
        releaseYear: answer['release_year'] as int? ?? releaseYear,
        genre: answer['genre'] as String? ?? genre,
        roundToken: roundToken,
        poolSize: poolSize,
      );

  Track copyWith({String? previewUrl}) => Track(
        id: id,
        title: title,
        artist: artist,
        previewUrl: previewUrl ?? this.previewUrl,
        coverUrl: coverUrl,
        releaseYear: releaseYear,
        genre: genre,
        roundToken: roundToken,
        poolSize: poolSize,
      );

  @override
  List<Object?> get props =>
      [id, title, artist, previewUrl, coverUrl, releaseYear, genre, roundToken];
}
