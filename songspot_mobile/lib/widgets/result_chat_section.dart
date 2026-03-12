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
  final ValueChanged<Message>? onRetryFailedMessage;

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
    this.onRetryFailedMessage,
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
            onRetry: onRetryFailedMessage,
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
                onRetry: onRetryFailedMessage,
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
  final ValueChanged<Message>? onRetry;

  const _ResultChatBubble({
    required this.message,
    required this.currentUserId,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrentUser = message.user.id == currentUserId;
    final footerColor = isCurrentUser ? Colors.white70 : AppTheme.textSecondary;
    final showRetry = isCurrentUser && message.isFailed && onRetry != null;
    final bubbleOpacity = message.isSending ? 0.82 : 1.0;
    Widget? statusIndicator;
    if (message.isSending) {
      statusIndicator = SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(
          strokeWidth: 1.8,
          valueColor: AlwaysStoppedAnimation<Color>(footerColor),
        ),
      );
    } else if (showRetry) {
      statusIndicator = GestureDetector(
        onTap: () => onRetry?.call(message),
        child: Icon(Icons.refresh_rounded, size: 13, color: footerColor),
      );
    } else if (message.isFailed) {
      statusIndicator = Icon(Icons.error_outline, size: 12, color: footerColor);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Opacity(
          opacity: bubbleOpacity,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: isCurrentUser ? AppTheme.primaryGradient : null,
              color: isCurrentUser ? null : AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: message.isFailed
                  ? Border.all(
                      color: isCurrentUser
                          ? Colors.white.withValues(alpha: 0.5)
                          : AppTheme.errorColor.withValues(alpha: 0.5),
                    )
                  : null,
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isCurrentUser) ...[
                      SizedBox(
                        width: 16,
                        child: Center(child: statusIndicator),
                      ),
                      const SizedBox(width: 6),
                    ] else if (statusIndicator != null) ...[
                      statusIndicator,
                      const SizedBox(width: 6),
                    ],
                    Text(
                      DateFormat.Hm().format(message.createdAt.toLocal()),
                      style: TextStyle(fontSize: 10, color: footerColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
