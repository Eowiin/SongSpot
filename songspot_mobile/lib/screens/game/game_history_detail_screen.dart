import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/history_day.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

class GameHistoryDetailScreen extends StatefulWidget {
  final String roomId;
  final String date;

  const GameHistoryDetailScreen({
    super.key,
    required this.roomId,
    required this.date,
  });

  @override
  State<GameHistoryDetailScreen> createState() =>
      _GameHistoryDetailScreenState();
}

class _GameHistoryDetailScreenState extends State<GameHistoryDetailScreen> {
  final ApiService _apiService = ApiService();
  HistoryDayDetail? _detail;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _apiService.getRoomHistoryDetail(
        widget.roomId,
        widget.date,
      );
      if (mounted) {
        setState(() {
          _detail = HistoryDayDetail.fromJson(data);
          _isLoading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat(
      'EEEE, MMM d yyyy',
    ).format(DateTime.parse(widget.date));

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new),
                      onPressed: () => Navigator.of(context).pop(),
                      color: AppTheme.textPrimary,
                    ),
                    Flexible(
                      child: Text(
                        dateLabel,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primaryColor,
                        ),
                      )
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: AppTheme.errorColor,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _error!,
                                style: const TextStyle(
                                  color: AppTheme.errorColor,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: _load,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _buildContent(_detail!),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(HistoryDayDetail detail) {
    final currentUserId = context.read<AuthProvider>().user?.id;
    final session = detail.mySession;

    return SingleChildScrollView(
      padding: AppTheme.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Song card ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppTheme.cardGradient,
              borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
            ),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: detail.track.coverUrl != null
                      ? Image.network(
                          detail.track.coverUrl!,
                          width: 180,
                          height: 180,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _albumPlaceholder(),
                        )
                      : _albumPlaceholder(),
                ),
                const SizedBox(height: 16),
                Text(
                  detail.track.title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  detail.track.artist,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // My result badge
                if (session != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: session.correctGuess
                          ? AppTheme.successColor.withValues(alpha: 0.2)
                          : AppTheme.errorColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          session.correctGuess
                              ? Icons.check_circle
                              : Icons.cancel,
                          color: session.correctGuess
                              ? AppTheme.successColor
                              : AppTheme.errorColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          session.correctGuess
                              ? '+${session.pointsEarned ?? 0} points (Snippet ${session.currentSnippet})'
                              : 'Not guessed',
                          style: TextStyle(
                            color: session.correctGuess
                                ? AppTheme.successColor
                                : AppTheme.errorColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'You didn\'t play this day',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Leaderboard ────────────────────────────────────────────────
          Text("Results", style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),

          if (detail.leaderboard.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
              ),
              child: Text(
                'Nobody guessed this day',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            )
          else
            ...detail.leaderboard.asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final e = entry.value;
              Color rankColor;
              if (rank == 1) {
                rankColor = const Color(0xFFFFD700);
              } else if (rank == 2) {
                rankColor = const Color(0xFFC0C0C0);
              } else if (rank == 3) {
                rankColor = const Color(0xFFCD7F32);
              } else {
                rankColor = AppTheme.textSecondary;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(
                    AppTheme.cardBorderRadius,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: rankColor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$rank',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: rankColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.username,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            'Snippet ${e.snippetNumber}${e.completedAt != null ? ' · ${DateFormat.Hm().format(e.completedAt!.toLocal())}' : ''}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${e.pointsEarned}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 24),

          // ── Chat ──────────────────────────────────────────────────────
          Text('Chat', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),

          if (detail.messages.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  const Icon(
                    Icons.chat_bubble_outline,
                    size: 40,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No messages that day',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          else
            ...detail.messages.map((msg) {
              final isMe = msg.userId == currentUserId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isMe
                          ? AppTheme.primaryColor.withValues(alpha: 0.2)
                          : AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (!isMe)
                          Text(
                            msg.username,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        Text(
                          msg.message,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat.Hm().format(msg.createdAt.toLocal()),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _albumPlaceholder() {
    return Container(
      width: 180,
      height: 180,
      color: AppTheme.surfaceColor,
      child: const Icon(Icons.album, size: 80, color: AppTheme.primaryColor),
    );
  }
}
