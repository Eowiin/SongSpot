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
  List<Object?> get props => [
    track,
    orderInPack,
    vocalsUrl,
    drumsUrl,
    bassUrl,
    otherUrl,
  ];
}

class SongPack extends Equatable {
  final String id;
  final String name;
  final String description;
  final String? iconUrl;
  final String? category;
  final int trackCount;
  final int priceCoins;
  final bool isFree;
  final bool autoUnlock;
  final bool isOwned;
  final bool isActive;
  final bool isCompleted;
  final bool canActivate;
  final DateTime? activatedOn;
  final DateTime? completedOn;
  final int totalDays;
  final int? currentDay;
  final int? remainingDays;
  final DateTime createdAt;
  final List<PackTrack>? tracks;

  const SongPack({
    required this.id,
    required this.name,
    required this.description,
    this.iconUrl,
    this.category,
    required this.trackCount,
    required this.priceCoins,
    required this.isFree,
    required this.autoUnlock,
    required this.isOwned,
    this.isActive = false,
    this.isCompleted = false,
    this.canActivate = false,
    this.activatedOn,
    this.completedOn,
    this.totalDays = 0,
    this.currentDay,
    this.remainingDays,
    required this.createdAt,
    this.tracks,
  });

  factory SongPack.fromJson(Map<String, dynamic> json) {
    final activatedOnRaw = json['activated_on'] as String?;
    final completedOnRaw = json['completed_on'] as String?;
    return SongPack(
      id: json['id'].toString(),
      name: json['name'] as String,
      description: (json['description'] as String?) ?? '',
      iconUrl: json['icon_url'] as String?,
      category: json['category'] as String?,
      trackCount: json['track_count'] as int? ?? 0,
      priceCoins: json['price_coins'] as int? ?? 0,
      isFree: json['is_free'] as bool? ?? false,
      autoUnlock: json['auto_unlock'] as bool? ?? false,
      isOwned: json['is_owned'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? false,
      isCompleted: json['is_completed'] as bool? ?? false,
      canActivate: json['can_activate'] as bool? ?? false,
      activatedOn: activatedOnRaw != null
          ? DateTime.parse(activatedOnRaw)
          : null,
      completedOn: completedOnRaw != null
          ? DateTime.parse(completedOnRaw)
          : null,
      totalDays: json['total_days'] as int? ?? 0,
      currentDay: json['current_day'] as int?,
      remainingDays: json['remaining_days'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      tracks: json['tracks'] != null
          ? (json['tracks'] as List)
                .map((item) => PackTrack.fromJson(item as Map<String, dynamic>))
                .toList()
          : null,
    );
  }

  SongPack copyWith({
    String? id,
    String? name,
    String? description,
    String? iconUrl,
    String? category,
    int? trackCount,
    int? priceCoins,
    bool? isFree,
    bool? autoUnlock,
    bool? isOwned,
    bool? isActive,
    bool? isCompleted,
    bool? canActivate,
    DateTime? activatedOn,
    bool clearActivatedOn = false,
    DateTime? completedOn,
    bool clearCompletedOn = false,
    int? totalDays,
    int? currentDay,
    bool clearCurrentDay = false,
    int? remainingDays,
    bool clearRemainingDays = false,
    DateTime? createdAt,
    List<PackTrack>? tracks,
    bool clearTracks = false,
  }) {
    return SongPack(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      iconUrl: iconUrl ?? this.iconUrl,
      category: category ?? this.category,
      trackCount: trackCount ?? this.trackCount,
      priceCoins: priceCoins ?? this.priceCoins,
      isFree: isFree ?? this.isFree,
      autoUnlock: autoUnlock ?? this.autoUnlock,
      isOwned: isOwned ?? this.isOwned,
      isActive: isActive ?? this.isActive,
      isCompleted: isCompleted ?? this.isCompleted,
      canActivate: canActivate ?? this.canActivate,
      activatedOn: clearActivatedOn ? null : (activatedOn ?? this.activatedOn),
      completedOn: clearCompletedOn ? null : (completedOn ?? this.completedOn),
      totalDays: totalDays ?? this.totalDays,
      currentDay: clearCurrentDay ? null : (currentDay ?? this.currentDay),
      remainingDays: clearRemainingDays
          ? null
          : (remainingDays ?? this.remainingDays),
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
    priceCoins,
    isFree,
    autoUnlock,
    isOwned,
    isActive,
    isCompleted,
    canActivate,
    activatedOn,
    completedOn,
    totalDays,
    currentDay,
    remainingDays,
    createdAt,
    tracks,
  ];
}
