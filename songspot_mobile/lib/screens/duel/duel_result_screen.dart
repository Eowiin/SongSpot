import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/duel_provider.dart';

class DuelResultScreen extends StatelessWidget {
  const DuelResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final duel = context.read<DuelProvider>();
    final end = duel.matchEnd;
    if (end == null) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
      );
    }

    final isWin = end.winner == 'player';
    final isDraw = end.winner == 'draw';
    final eloPositive = end.eloChange >= 0;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        // Scrolls once the content outgrows the viewport (large text scales,
        // short screens); the Spacer still pins the actions to the bottom
        // when there is room to spare.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 32),
                    _buildWinnerBanner(isWin, isDraw, l10n),
                    const SizedBox(height: 20),
                    _buildEloChange(end.eloChange, end.newElo, eloPositive, l10n),
                    const SizedBox(height: 24),
                    _buildScoreRow(end.playerFinalScore, end.opponentFinalScore, duel, l10n),
                    const SizedBox(height: 24),
                    if (duel.lastRoundResult != null) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l10n.duelMatchSummary,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSummaryCard(duel, l10n),
                    ],
                      const Spacer(),
                      _buildActions(context, duel, l10n),
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

  Widget _buildWinnerBanner(bool isWin, bool isDraw, AppLocalizations l10n) {
    final (emoji, label, color) = isDraw
        ? ('🤝', l10n.duelDraw, AppTheme.textSecondary)
        : isWin
            ? ('🏆', l10n.duelWin, AppTheme.successColor)
            : ('💀', l10n.duelLost, AppTheme.errorColor);

    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 64)),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 36,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildEloChange(int change, int newElo, bool positive, AppLocalizations l10n) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          positive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          color: positive ? AppTheme.successColor : AppTheme.errorColor,
          size: 20,
        ),
        const SizedBox(width: 4),
        Text(
          '${positive ? '+' : ''}$change ELO',
          style: TextStyle(
            color: positive ? AppTheme.successColor : AppTheme.errorColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          l10n.duelNewElo(newElo),
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildScoreRow(int playerScore, int opponentScore, DuelProvider duel, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 32),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildScoreCell(l10n.duelYou, '$playerScore', AppTheme.primaryColor),
          const Text('—', style: TextStyle(color: AppTheme.textSecondary, fontSize: 24)),
          _buildScoreCell(
            duel.opponent?.username ?? 'Opponent',
            '$opponentScore',
            AppTheme.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildScoreCell(String label, String score, Color color) {
    return Column(
      children: [
        Text(
          score,
          style: TextStyle(color: color, fontSize: 36, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      ],
    );
  }

  Widget _buildSummaryCard(DuelProvider duel, AppLocalizations l10n) {
    final result = duel.lastRoundResult!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.duelRoundLabel(result.round),
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                ),
                Text(
                  result.track.title ?? '?',
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  result.track.artist ?? '',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildRoundResultBadge(result.player.correct, result.player.points),
          const SizedBox(width: 8),
          Text(l10n.duelVs, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          const SizedBox(width: 8),
          _buildRoundResultBadge(result.opponent.correct, result.opponent.points),
        ],
      ),
    );
  }

  Widget _buildRoundResultBadge(bool correct, int points) {
    return Column(
      children: [
        Icon(
          correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: correct ? AppTheme.successColor : AppTheme.errorColor,
          size: 20,
        ),
        Text(
          correct ? '+$points' : '0',
          style: TextStyle(
            color: correct ? AppTheme.successColor : AppTheme.errorColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context, DuelProvider duel, AppLocalizations l10n) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextButton(
              onPressed: () => context.read<DuelProvider>().reset(),
              style: TextButton.styleFrom(
                // minimumSize instead of a fixed 52px box: the button grows
                // when the label wraps at large text scales.
                minimumSize: const Size.fromHeight(52),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                l10n.duelPlayAgain,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              duel.disconnect();
              Navigator.of(context).pop();
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(
              l10n.duelBackToHome,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }
}
