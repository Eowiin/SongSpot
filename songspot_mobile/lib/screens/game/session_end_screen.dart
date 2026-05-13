import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/category.dart';
import '../../models/game_score.dart';
import '../../providers/game_session_provider.dart';
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
  final Difficulty difficulty;
  final SessionEndReason endReason;

  const SessionEndScreen({
    super.key,
    this.score,
    required this.songsPlayed,
    required this.songsCorrect,
    required this.bestStreak,
    required this.totalScore,
    this.category,
    this.artistFilter,
    this.difficulty = Difficulty.medium,
    this.endReason = SessionEndReason.quit,
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
              const SizedBox(height: 16),
              _buildBadgesRow(),
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

    switch (endReason) {
      case SessionEndReason.poolCleared:
        emoji = '🏆';
        headline = 'You cleared it!';
      case SessionEndReason.outOfLives:
        emoji = '💀';
        headline = 'Out of lives!';
      case SessionEndReason.quit:
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

  Widget _buildBadgesRow() {
    final diffColor = _difficultyColor(difficulty);
    final multiplierText = '×${difficulty.scoreMultiplier.toStringAsFixed(1)}';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildChip(
          label: difficulty.label,
          sublabel: multiplierText,
          color: diffColor,
          icon: Icons.tune_rounded,
        ),
      ],
    );
  }

  Widget _buildChip({
    required String label,
    required String sublabel,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            '$label  $sublabel',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Color _difficultyColor(Difficulty d) => switch (d) {
        Difficulty.easy => const Color(0xFF4CAF50),
        Difficulty.medium => const Color(0xFFFF9800),
        Difficulty.hard => const Color(0xFFE53935),
      };

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
                    difficulty: difficulty,
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
