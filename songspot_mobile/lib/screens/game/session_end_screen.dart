import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../config/difficulty_style.dart';
import '../../config/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/category.dart';
import '../../models/game_score.dart';
import '../../models/solo_setup.dart';
import '../../providers/game_session_provider.dart';
import 'solo_setup_sheet.dart';

class SessionEndScreen extends StatelessWidget {
  final GameScore? score;
  final int songsPlayed;
  final int songsCorrect;
  final int bestStreak;
  final int totalScore;
  final Category? category;
  final String? artistFilter;
  /// Carried through so replaying an artist session picks the same Deezer
  /// entity rather than re-resolving an ambiguous name.
  final int? artistDeezerId;
  final bool mix;
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
    this.artistDeezerId,
    this.mix = false,
    this.difficulty = Difficulty.medium,
    this.endReason = SessionEndReason.quit,
  });

  double get _accuracy =>
      songsPlayed == 0 ? 0 : (songsCorrect / songsPlayed * 100);

  /// The run that just ended, as the solo panel sees it.
  SoloSetup get _setup => SoloSetup(
        category: category,
        artistName: artistFilter,
        artistDeezerId: artistDeezerId,
        difficulty: difficulty,
      );

  Future<void> _changeSettings(BuildContext context) async {
    final setup = await showSoloSetupSheet(context, _setup);
    if (setup == null || !context.mounted) return;
    await startSoloRun(context, setup, replace: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        // The content was a bare Column: at large text scales it simply ran
        // past the bottom of the screen. It now scrolls when it no longer
        // fits, while the Spacer still pins the actions to the bottom
        // whenever there is room to spare.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: ResponsiveCenter(
                  maxWidth: 620,
                  child: Column(
                    children: [
                      const SizedBox(height: 40),
                      _buildTitle(l10n),
                      const SizedBox(height: 32),
                      _buildStatsCard(l10n),
                      const SizedBox(height: 16),
                      _buildBadgesRow(l10n),
                      const Spacer(),
                      _buildActions(context),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(AppLocalizations l10n) {
    final String emoji;
    final String headline;

    switch (endReason) {
      case SessionEndReason.poolCleared:
        emoji = '🏆';
        headline = l10n.sessionEndHeadlineCleared;
      case SessionEndReason.outOfLives:
        emoji = '💀';
        headline = l10n.sessionEndHeadlineOutOfLives;
      case SessionEndReason.quit:
        if (songsPlayed == 0) {
          emoji = '🎵';
          headline = l10n.sessionEndHeadlineEnded;
        } else if (_accuracy >= 80) {
          emoji = '🔥';
          headline = l10n.sessionEndHeadlineOnFire;
        } else if (_accuracy >= 50) {
          emoji = '🎯';
          headline = l10n.sessionEndHeadlineNiceRun;
        } else {
          emoji = '🎵';
          headline = l10n.sessionEndHeadlineGoodTry;
        }
    }

    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 56)),
        const SizedBox(height: 12),
        Text(
          headline.toUpperCase(),
          textAlign: TextAlign.center,
          style: AppTheme.display(28),
        ),
        if (mix || category != null || artistFilter != null) ...[
          const SizedBox(height: 6),
          Text(
            mix ? l10n.mixLabel : category?.name ?? artistFilter ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.ink2, fontSize: 15),
          ),
        ],
      ],
    );
  }

  Widget _buildStatsCard(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDeep,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
        border: Border.all(color: AppTheme.line),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat(l10n.sessionEndStatScore, '$totalScore', AppTheme.primaryColor),
          _buildDivider(),
          _buildStat(l10n.sessionEndStatStreak, '🔥 $bestStreak', const Color(0xFFFF6B35)),
          _buildDivider(),
          _buildStat(
              l10n.sessionEndStatAccuracy, '${_accuracy.toStringAsFixed(0)}%', const Color(0xFF4CAF50)),
          _buildDivider(),
          _buildStat(l10n.sessionEndStatSongs, '$songsPlayed', AppTheme.textSecondary),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, Color valueColor) {
    // Four localized labels share one row here, so each column takes an equal
    // slice and shrinks its value rather than overrunning at large text scales.
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: AppTheme.display(22, color: valueColor),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.kicker(color: AppTheme.ink3, size: 9.5),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 36,
      color: AppTheme.line,
    );
  }

  Widget _buildBadgesRow(AppLocalizations l10n) {
    final diffColor = difficulty.color;
    final multiplierText = '×${difficulty.scoreMultiplier.toStringAsFixed(1)}';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Flexible so the chip's own Flexible label can shrink: "Difficile"
        // at a large text scale is wider than the screen allows.
        Flexible(
          child: _buildChip(
            label: difficulty.localizedName(l10n),
            sublabel: multiplierText,
            color: diffColor,
            icon: Icons.tune_rounded,
          ),
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.borderRadius),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$label  $sublabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => startSoloRun(context, _setup, replace: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.borderRadius)),
              elevation: 0,
            ),
            child: Text(
              l10n.sessionEndPlayAgain,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _changeSettings(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.3)),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.borderRadius)),
            ),
            child: Text(
              l10n.sessionEndChangeSettings,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context)
              .popUntil((route) => route.isFirst),
          child: Text(
            l10n.sessionEndBackToHome,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      ],
    );
  }
}
