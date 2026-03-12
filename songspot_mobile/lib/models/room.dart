import 'package:equatable/equatable.dart';
import 'pack.dart';
import 'user.dart';

class RoomUser extends Equatable {
  final User user;
  final DateTime joinedAt;

  const RoomUser({
    required this.user,
    required this.joinedAt,
  });

  factory RoomUser.fromJson(Map<String, dynamic> json) {
    return RoomUser(
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }

  @override
  List<Object?> get props => [user, joinedAt];
}

class Room extends Equatable {
  final String id;
  final String roomCode;
  final String? name;
  final User hostUser;
  final List<RoomUser> users;
  final int userCount;
  final SongPack? activePack;
  final DateTime createdAt;

  const Room({
    required this.id,
    required this.roomCode,
    this.name,
    required this.hostUser,
    required this.users,
    required this.userCount,
    this.activePack,
    required this.createdAt,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'].toString(),
      roomCode: json['room_code'] as String,
      name: json['name'] as String?,
      hostUser: User.fromJson(json['host_user'] as Map<String, dynamic>),
      users: (json['users'] as List)
          .map((u) => RoomUser.fromJson(u as Map<String, dynamic>))
          .toList(),
      userCount: json['user_count'] as int,
      activePack: json['active_pack'] != null
          ? SongPack.fromJson(json['active_pack'] as Map<String, dynamic>)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
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
    createdAt,
  ];
}
