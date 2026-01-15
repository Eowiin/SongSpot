import 'package:equatable/equatable.dart';
import 'user.dart';

class Message extends Equatable {
  final String id;
  final User user;
  final String message;
  final DateTime createdAt;

  const Message({
    required this.id,
    required this.user,
    required this.message,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'].toString(),
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      message: json['message'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id, user, message, createdAt];
}
