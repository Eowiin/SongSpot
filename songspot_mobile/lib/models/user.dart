import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String id;
  final String email;
  final String username;
  final int currentStreak;

  const User({
    required this.id,
    required this.email,
    required this.username,
    this.currentStreak = 0,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'].toString(),
      email: json['email'] as String,
      username: json['username'] as String,
      currentStreak: json['current_streak'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'current_streak': currentStreak,
    };
  }

  @override
  List<Object?> get props => [id, email, username, currentStreak];
}
