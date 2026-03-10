import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_theme.dart';
import '../models/message.dart';

class ResultChatSection extends StatelessWidget {
  final String title;
  final String emptyTitle;
  final String? emptySubtitle;
  final List<Message> messages;
  final String? currentUserId;
  final int maxMessages;
  final double? maxHeight;
  final ScrollController? scrollController;

  const ResultChatSection({
    super.key,
    required this.title,
    required this.emptyTitle,
    this.emptySubtitle,
    required this.messages,
    required this.currentUserId,
    this.maxMessages = 12,
    this.maxHeight,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final displayMessages = messages
        .take(maxMessages)
        .toList()
        .reversed
        .toList();

    Widget content;
    if (messages.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              size: 40,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(emptyTitle, style: Theme.of(context).textTheme.titleMedium),
            if ((emptySubtitle ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                emptySubtitle!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      );
    } else if (maxHeight != null) {
      content = SizedBox(
        height: maxHeight,
        child: ListView.builder(
          controller: scrollController,
          shrinkWrap: true,
          itemCount: displayMessages.length,
          itemBuilder: (context, index) => _ResultChatBubble(
            message: displayMessages[index],
            currentUserId: currentUserId,
          ),
        ),
      );
    } else {
      content = Column(
        children: displayMessages
            .map(
              (message) => _ResultChatBubble(
                message: message,
                currentUserId: currentUserId,
              ),
            )
            .toList(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        content,
      ],
    );
  }
}

class _ResultChatBubble extends StatelessWidget {
  final Message message;
  final String? currentUserId;

  const _ResultChatBubble({required this.message, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    final isCurrentUser = message.user.id == currentUserId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: isCurrentUser ? AppTheme.primaryGradient : null,
            color: isCurrentUser ? null : AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: isCurrentUser
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (!isCurrentUser) ...[
                Text(
                  message.user.username,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                message.message,
                textWidthBasis: TextWidthBasis.longestLine,
                style: TextStyle(
                  color: isCurrentUser ? Colors.white : AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat.Hm().format(message.createdAt.toLocal()),
                style: TextStyle(
                  fontSize: 10,
                  color: isCurrentUser
                      ? Colors.white70
                      : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
