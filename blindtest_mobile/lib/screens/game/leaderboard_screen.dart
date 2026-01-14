import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/app_theme.dart';
import '../../providers/game_provider.dart';

class LeaderboardScreen extends StatefulWidget {
  final String roomId;

  const LeaderboardScreen({super.key, required this.roomId});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GameProvider>().loadLeaderboard(widget.roomId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: Consumer<GameProvider>(
          builder: (context, gameProvider, _) {
            if (gameProvider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            final leaderboard = gameProvider.leaderboard;

            if (leaderboard.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.emoji_events_outlined,
                      size: 80,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No scores yet',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Be the first to guess the song!',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: AppTheme.pagePadding,
              itemCount: leaderboard.length,
              itemBuilder: (context, index) {
                final entry = leaderboard[index];
                final rank = index + 1;
                final isTopThree = rank <= 3;

                Color rankColor;
                IconData? medalIcon;

                if (rank == 1) {
                  rankColor = const Color(0xFFFFD700); // Gold
                  medalIcon = Icons.emoji_events;
                } else if (rank == 2) {
                  rankColor = const Color(0xFFC0C0C0); // Silver
                  medalIcon = Icons.emoji_events;
                } else if (rank == 3) {
                  rankColor = const Color(0xFFCD7F32); // Bronze
                  medalIcon = Icons.emoji_events;
                } else {
                  rankColor = AppTheme.textSecondary;
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: isTopThree ? AppTheme.cardGradient : null,
                    color: isTopThree ? null : AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
                    border: isTopThree
                        ? Border.all(color: rankColor.withValues(alpha: 0.3), width: 2)
                        : null,
                  ),
                  child: Row(
                    children: [
                      // Rank
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: rankColor.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: medalIcon != null
                              ? Icon(medalIcon, color: rankColor, size: 30)
                              : Text(
                                  '$rank',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: rankColor,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // User Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.user.username,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Snippet ${entry.snippetNumber} • ${DateFormat.Hm().format(entry.completedAt.toLocal())}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),

                      // Points
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${entry.pointsEarned} pts',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
