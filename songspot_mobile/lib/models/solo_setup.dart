import '../providers/game_session_provider.dart';
import 'category.dart';

/// What a solo run plays (every genre, one category or one artist) and how
/// hard it is.
///
/// Remembered between runs, so the home screen can start the next one in a
/// single tap. At most one of [category] and [artistName] is set; neither
/// means every genre.
class SoloSetup {
  final Category? category;
  final String? artistName;
  final int? artistDeezerId;
  final Difficulty difficulty;

  const SoloSetup({
    this.category,
    this.artistName,
    this.artistDeezerId,
    this.difficulty = Difficulty.medium,
  });

  /// Before the first run: every genre, medium.
  static const initial = SoloSetup();

  bool get isMix => category == null && artistName == null;

  SoloSetup withMix() => SoloSetup(difficulty: difficulty);

  SoloSetup withCategory(Category category) =>
      SoloSetup(category: category, difficulty: difficulty);

  SoloSetup withArtist(String name, int? deezerId) =>
      SoloSetup(artistName: name, artistDeezerId: deezerId, difficulty: difficulty);

  SoloSetup withDifficulty(Difficulty difficulty) => SoloSetup(
        category: category,
        artistName: artistName,
        artistDeezerId: artistDeezerId,
        difficulty: difficulty,
      );

  Map<String, dynamic> toJson() => {
        'difficulty': difficulty.name,
        if (category != null)
          'category': {
            'id': category!.id,
            'name': category!.name,
            'category': category!.category,
            'track_count': category!.trackCount,
          },
        if (artistName != null) 'artist_name': artistName,
        if (artistDeezerId != null) 'artist_deezer_id': artistDeezerId,
      };

  factory SoloSetup.fromJson(Map<String, dynamic> json) {
    final category = json['category'];
    return SoloSetup(
      category: category is Map<String, dynamic> ? Category.fromJson(category) : null,
      artistName: json['artist_name'] as String?,
      artistDeezerId: json['artist_deezer_id'] as int?,
      difficulty: Difficulty.values.firstWhere(
        (d) => d.name == json['difficulty'],
        orElse: () => Difficulty.medium,
      ),
    );
  }
}
