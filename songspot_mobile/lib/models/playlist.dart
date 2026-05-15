import 'package:equatable/equatable.dart';
import 'track.dart';

class PlaylistTrack extends Equatable {
  final Track track;
  final int orderInPlaylist;

  const PlaylistTrack({
    required this.track,
    required this.orderInPlaylist,
  });

  factory PlaylistTrack.fromJson(Map<String, dynamic> json) {
    return PlaylistTrack(
      track: Track.fromJson(json['track'] as Map<String, dynamic>),
      orderInPlaylist: json['order_in_playlist'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [track, orderInPlaylist];
}

class Playlist extends Equatable {
  final String id;
  final String name;
  final String description;
  final String? iconUrl;
  final String? category;
  final int trackCount;
  final DateTime createdAt;
  final List<PlaylistTrack>? tracks;

  const Playlist({
    required this.id,
    required this.name,
    required this.description,
    this.iconUrl,
    this.category,
    required this.trackCount,
    required this.createdAt,
    this.tracks,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'].toString(),
      name: json['name'] as String,
      description: (json['description'] as String?) ?? '',
      iconUrl: json['icon_url'] as String?,
      category: json['category'] as String?,
      trackCount: json['track_count'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      tracks: json['tracks'] != null
          ? (json['tracks'] as List)
                .map((item) => PlaylistTrack.fromJson(item as Map<String, dynamic>))
                .toList()
          : null,
    );
  }

  Playlist copyWith({
    String? id,
    String? name,
    String? description,
    String? iconUrl,
    String? category,
    int? trackCount,
    DateTime? createdAt,
    List<PlaylistTrack>? tracks,
    bool clearTracks = false,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      iconUrl: iconUrl ?? this.iconUrl,
      category: category ?? this.category,
      trackCount: trackCount ?? this.trackCount,
      createdAt: createdAt ?? this.createdAt,
      tracks: clearTracks ? null : (tracks ?? this.tracks),
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    description,
    iconUrl,
    category,
    trackCount,
    createdAt,
    tracks,
  ];
}
