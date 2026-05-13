import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/category.dart';
import '../../models/game_score.dart';
import 'category_select_screen.dart';
import 'game_screen.dart';

class SessionEndScreen extends StatelessWidget {
  final GameScore? score;
  final int songsPlayed;
  final int songsCorrect;
  final int bestStreak;
  final int totalScore;
  final Category? category;
  final String? artistFilter;

  const SessionEndScreen({
    super.key,
    this.score,
    required this.songsPlayed,
    required this.songsCorrect,
    required this.bestStreak,
    required this.totalScore,
    this.category,
    this.artistFilter,
  });

  double get _accuracy =>
      songsPlayed == 0 ? 0 : (songsCorrect / songsPlayed * 100);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              _buildTitle(),
              const SizedBox(height: 32),
              _buildStatsCard(),
              const SizedBox(height: 32),
              _buildPersonalBestBadge(),
              const Spacer(),
              _buildActions(context),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    final String emoji;
    final String headline;

    if (songsPlayed == 0) {
      emoji = '🎵';
      headline = 'Session ended';
    } else if (_accuracy >= 80) {
      emoji = '🔥';
      headline = 'On fire!';
    } else if (_accuracy >= 50) {
      emoji = '🎯';
      headline = 'Nice run!';
    } else {
      emoji = '🎵';
      headline = 'Good try!';
    }

    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 56)),
        const SizedBox(height: 12),
        Text(
          headline,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (category != null || artistFilter != null) ...[
          const SizedBox(height: 6),
          Text(
            category?.name ?? artistFilter ?? '',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15),
          ),
        ],
      ],
    );
  }

  Widget _buildStatsCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat('Score', '$totalScore', AppTheme.primaryColor),
          _buildDivider(),
          _buildStat('Streak', '🔥 $bestStreak', const Color(0xFFFF6B35)),
          _buildDivider(),
          _buildStat(
              'Accuracy', '${_accuracy.toStringAsFixed(0)}%', const Color(0xFF4CAF50)),
          _buildDivider(),
          _buildStat('Songs', '$songsPlayed', AppTheme.textSecondary),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 36,
      color: Colors.white.withOpacity(0.1),
    );
  }

  Widget _buildPersonalBestBadge() {
    if (score == null) return const SizedBox.shrink();

    // Check if any field is a personal best by comparing to score if available
    // The backend updates UserBest and returns the GameScore — we show a badge
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events_rounded,
              color: AppTheme.primaryColor, size: 18),
          const SizedBox(width: 8),
          const Text(
            'Score submitted to leaderboard',
            style: TextStyle(
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => GameScreen(
                    category: category,
                    artistFilter: artistFilter,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: const Text(
              'Play again',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (_) => const CategorySelectScreen()),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: BorderSide(color: AppTheme.textSecondary.withOpacity(0.3)),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text(
              'Change category',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context)
              .popUntil((route) => route.isFirst),
          child: const Text(
            'Back to home',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      ],
    );
  }
}
