import 'package:equatable/equatable.dart';
import 'playlist.dart';
import 'user.dart';

class RoomUser extends Equatable {
  final User user;
  final DateTime joinedAt;

  const RoomUser({required this.user, required this.joinedAt});

  factory RoomUser.fromJson(Map<String, dynamic> json) {
    return RoomUser(
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }

  @override
  List<Object?> get props => [user, joinedAt];
}

class RoomDailyMode extends Equatable {
  final String mode;
  final String label;
  final String subtitle;
  final int costCoins;
  final bool isFree;
  final bool isEnabled;
  final bool isUnlocked;
  final DateTime? unlockedUntil;
  final int progressCoins;
  final int remainingCoins;
  final int contributorCount;

  const RoomDailyMode({
    required this.mode,
    required this.label,
    required this.subtitle,
    required this.costCoins,
    required this.isFree,
    required this.isEnabled,
    required this.isUnlocked,
    this.unlockedUntil,
    required this.progressCoins,
    required this.remainingCoins,
    required this.contributorCount,
  });

  factory RoomDailyMode.fromJson(Map<String, dynamic> json) {
    final unlockedUntilRaw = json['unlocked_until'] as String?;
    return RoomDailyMode(
      mode: json['mode'] as String,
      label: json['label'] as String? ?? json['mode'] as String,
      subtitle: json['subtitle'] as String? ?? '',
      costCoins: json['cost_coins'] as int? ?? 0,
      isFree: json['is_free'] as bool? ?? false,
      isEnabled: json['is_enabled'] as bool? ?? true,
      isUnlocked: json['is_unlocked'] as bool? ?? false,
      unlockedUntil: unlockedUntilRaw != null
          ? DateTime.parse(unlockedUntilRaw)
          : null,
      progressCoins: json['progress_coins'] as int? ?? 0,
      remainingCoins: json['remaining_coins'] as int? ?? 0,
      contributorCount: json['contributor_count'] as int? ?? 0,
    );
  }

  bool get isPlayable => isFree || isUnlocked;

  RoomDailyMode copyWith({
    String? mode,
    String? label,
    String? subtitle,
    int? costCoins,
    bool? isFree,
    bool? isEnabled,
    bool? isUnlocked,
    DateTime? unlockedUntil,
    bool clearUnlockedUntil = false,
    int? progressCoins,
    int? remainingCoins,
    int? contributorCount,
  }) {
    return RoomDailyMode(
      mode: mode ?? this.mode,
      label: label ?? this.label,
      subtitle: subtitle ?? this.subtitle,
      costCoins: costCoins ?? this.costCoins,
      isFree: isFree ?? this.isFree,
      isEnabled: isEnabled ?? this.isEnabled,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      unlockedUntil: clearUnlockedUntil
          ? null
          : (unlockedUntil ?? this.unlockedUntil),
      progressCoins: progressCoins ?? this.progressCoins,
      remainingCoins: remainingCoins ?? this.remainingCoins,
      contributorCount: contributorCount ?? this.contributorCount,
    );
  }

  @override
  List<Object?> get props => [
    mode,
    label,
    subtitle,
    costCoins,
    isFree,
    isEnabled,
    isUnlocked,
    unlockedUntil,
    progressCoins,
    remainingCoins,
    contributorCount,
  ];
}

class Room extends Equatable {
  final String id;
  final String roomCode;
  final String? name;
  final User hostUser;
  final List<RoomUser> users;
  final int userCount;
  final Playlist? activePack;
  final List<RoomDailyMode> dailyModes;
  final DateTime createdAt;

  const Room({
    required this.id,
    required this.roomCode,
    this.name,
    required this.hostUser,
    required this.users,
    required this.userCount,
    this.activePack,
    this.dailyModes = const [],
    required this.createdAt,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'].toString(),
      roomCode: json['room_code'] as String,
      name: json['name'] as String?,
      hostUser: User.fromJson(json['host_user'] as Map<String, dynamic>),
      users: List.unmodifiable(
        (json['users'] as List)
            .map((u) => RoomUser.fromJson(u as Map<String, dynamic>))
            .toList(),
      ),
      userCount: json['user_count'] as int,
      activePack: json['active_pack'] != null
          ? Playlist.fromJson(json['active_pack'] as Map<String, dynamic>)
          : null,
      dailyModes: List.unmodifiable(
        (json['daily_modes'] as List<dynamic>? ?? const [])
            .map((item) => RoomDailyMode.fromJson(item as Map<String, dynamic>))
            .toList(),
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Room copyWith({
    String? id,
    String? roomCode,
    String? name,
    User? hostUser,
    List<RoomUser>? users,
    int? userCount,
    Playlist? activePack,
    bool clearActivePack = false,
    List<RoomDailyMode>? dailyModes,
    DateTime? createdAt,
  }) {
    return Room(
      id: id ?? this.id,
      roomCode: roomCode ?? this.roomCode,
      name: name ?? this.name,
      hostUser: hostUser ?? this.hostUser,
      users: List.unmodifiable(users ?? this.users),
      userCount: userCount ?? this.userCount,
      activePack: clearActivePack ? null : (activePack ?? this.activePack),
      dailyModes: List.unmodifiable(dailyModes ?? this.dailyModes),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Returns the display name for the room (name if set, otherwise "Room CODE")
  String get displayName => name ?? 'Room $roomCode';

  bool isHost(String userId) => hostUser.id == userId;

  @override
  List<Object?> get props => [
    id,
    roomCode,
    name,
    hostUser,
    users,
    userCount,
    activePack,
    dailyModes,
    createdAt,
  ];
}
