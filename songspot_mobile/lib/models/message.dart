import 'package:equatable/equatable.dart';

import 'user.dart';

enum MessageDeliveryStatus { sending, sent, failed }

class Message extends Equatable {
  final String id;
  final User user;
  final String message;
  final DateTime createdAt;
  final String? clientMessageId;
  final MessageDeliveryStatus deliveryStatus;
  final String? failureReason;

  const Message({
    required this.id,
    required this.user,
    required this.message,
    required this.createdAt,
    this.clientMessageId,
    this.deliveryStatus = MessageDeliveryStatus.sent,
    this.failureReason,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'].toString(),
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      message: json['message'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      clientMessageId: json['client_message_id']?.toString(),
    );
  }

  factory Message.pending({
    required String clientMessageId,
    required User user,
    required String message,
  }) {
    return Message(
      id: 'local:$clientMessageId',
      user: user,
      message: message,
      createdAt: DateTime.now().toUtc(),
      clientMessageId: clientMessageId,
      deliveryStatus: MessageDeliveryStatus.sending,
    );
  }

  bool get isSending => deliveryStatus == MessageDeliveryStatus.sending;
  bool get isFailed => deliveryStatus == MessageDeliveryStatus.failed;

  Message copyWith({
    String? id,
    User? user,
    String? message,
    DateTime? createdAt,
    String? clientMessageId,
    MessageDeliveryStatus? deliveryStatus,
    String? failureReason,
    bool clearFailureReason = false,
  }) {
    return Message(
      id: id ?? this.id,
      user: user ?? this.user,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      failureReason: clearFailureReason
          ? null
          : (failureReason ?? this.failureReason),
    );
  }

  @override
  List<Object?> get props => [
    id,
    user,
    message,
    createdAt,
    clientMessageId,
    deliveryStatus,
    failureReason,
  ];
}
