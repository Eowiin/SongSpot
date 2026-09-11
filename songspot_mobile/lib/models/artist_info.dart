/// An artist the player can pick.
///
/// [deezerId] pins the choice to one Deezer entity, which matters because
/// names are ambiguous in ways that ruin a session: a search for "weeknd"
/// returns a 2 000-fan namesake and a covers act called "The Retro Weeknd"
/// alongside the real one. It is null only for favourites saved before the
/// app recorded IDs, which still resolve by name on the server.
class ArtistInfo {
  final String name;
  final String? pictureUrl;
  final int? deezerId;

  const ArtistInfo({required this.name, this.pictureUrl, this.deezerId});

  factory ArtistInfo.fromJson(Map<String, dynamic> j) => ArtistInfo(
        name: j['name'] as String,
        pictureUrl: j['picture_url'] as String?,
        deezerId: j['deezer_id'] as int?,
      );

  // Equality stays on the name so a favourite saved without an ID still
  // matches the same artist coming back from search with one.
  @override
  bool operator ==(Object other) => other is ArtistInfo && other.name == name;

  @override
  int get hashCode => name.hashCode;
}
