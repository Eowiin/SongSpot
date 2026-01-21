import 'package:equatable/equatable.dart';
import 'track.dart';

class PackTrack extends Equatable {
  final Track track;
  final int orderInPack;
  final String? vocalsUrl;
  final String? drumsUrl;
  final String? bassUrl;
  final String? otherUrl;

  const PackTrack({
    required this.track,
    required this.orderInPack,
    this.vocalsUrl,
    this.drumsUrl,
    this.bassUrl,
    this.otherUrl,
  });

  factory PackTrack.fromJson(Map<String, dynamic> json) {
    return PackTrack(
      track: Track.fromJson(json['track'] as Map<String, dynamic>),
      orderInPack: json['order_in_pack'] as int? ?? 0,
      vocalsUrl: json['vocals_url'] as String?,
      drumsUrl: json['drums_url'] as String?,
      bassUrl: json['bass_url'] as String?,
      otherUrl: json['other_url'] as String?,
    );
  }

  @override
  List<Object?> get props => [track, orderInPack, vocalsUrl, drumsUrl, bassUrl, otherUrl];
}

class SongPack extends Equatable {
  final String id;
  final String name;
  final String description;
  final String? iconUrl;
  final int trackCount;
  final int priceCoins;
  final bool isFree;
  final bool isFeatured;
  final bool isOwned;
  final DateTime createdAt;
  final List<PackTrack>? tracks;

  const SongPack({
    required this.id,
    required this.name,
    required this.description,
    this.iconUrl,
    required this.trackCount,
    required this.priceCoins,
    required this.isFree,
    required this.isFeatured,
    required this.isOwned,
    required this.createdAt,
    this.tracks,
  });

  factory SongPack.fromJson(Map<String, dynamic> json) {
    return SongPack(
      id: json['id'].toString(),
      name: json['name'] as String,
      description: (json['description'] as String?) ?? '',
      iconUrl: json['icon_url'] as String?,
      trackCount: json['track_count'] as int? ?? 0,
      priceCoins: json['price_coins'] as int? ?? 0,
      isFree: json['is_free'] as bool? ?? false,
      isFeatured: json['is_featured'] as bool? ?? false,
      isOwned: json['is_owned'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      tracks: json['tracks'] != null
          ? (json['tracks'] as List)
              .map((item) => PackTrack.fromJson(item as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        iconUrl,
        trackCount,
        priceCoins,
        isFree,
        isFeatured,
        isOwned,
        createdAt,
        tracks,
      ];
}
