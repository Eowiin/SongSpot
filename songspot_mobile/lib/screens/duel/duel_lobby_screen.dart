import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../config/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/duel_provider.dart';
import '../../models/duel.dart';

class DuelLobbyScreen extends StatefulWidget {
  const DuelLobbyScreen({super.key});

  @override
  State<DuelLobbyScreen> createState() => _DuelLobbyScreenState();
}

class _DuelLobbyScreenState extends State<DuelLobbyScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DuelProvider>().loadElo();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  void _onFindMatch() {
    final duel = context.read<DuelProvider>();
    duel.joinQueue();
    _elapsedSeconds = 0;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  void _onCancel() {
    _elapsedTimer?.cancel();
    context.read<DuelProvider>().leaveQueue();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Consumer<DuelProvider>(
      builder: (context, duel, _) {
        final isQueuing = duel.status == DuelStatus.queuing;

        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: AppBar(
            backgroundColor: AppTheme.backgroundColor,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textSecondary),
              onPressed: () {
                if (isQueuing) _onCancel();
                Navigator.pop(context);
              },
            ),
            title: const Text(
              '1v1',
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
          ),
          body: SafeArea(
            // Scrolls once the content outgrows the viewport (large text
            // scales, short screens); the Spacer still pins the bottom
            // section when there is room to spare.
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: ResponsiveCenter(
                      maxWidth: 680,
                      child: isQueuing
                          ? _buildSearchingState(duel, l10n)
                          : _buildIdleState(duel, l10n),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIdleState(DuelProvider duel, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 48),
        _buildEloCard(duel.elo, l10n),
        const SizedBox(height: 40),
        _buildInfoSection(l10n),
        const Spacer(),
        if (duel.status == DuelStatus.error && duel.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              duel.errorMessage!,
              style: const TextStyle(color: AppTheme.errorColor),
              textAlign: TextAlign.center,
            ),
          ),
        _buildFindMatchButton(l10n),

        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildSearchingState(DuelProvider duel, AppLocalizations l10n) {
    final minutes = _elapsedSeconds ~/ 60;
    final seconds = _elapsedSeconds % 60;
    final elapsed = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (_, _) => Transform.scale(
            scale: 0.9 + 0.1 * _pulseController.value,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.primaryColor.withValues(alpha: 0.6 + 0.4 * _pulseController.value),
                    AppTheme.primaryColor.withValues(alpha: 0.1),
                  ],
                ),
              ),
              child: const Icon(Icons.people_rounded, color: Colors.white, size: 52),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Text(
          l10n.duelFindingOpponent,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          elapsed,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
        ),
        const SizedBox(height: 48),
        TextButton(
          onPressed: _onCancel,
          child: Text(
            l10n.cancel,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
          ),
        ),
      ],
    ),
    );
  }

  Widget _buildEloCard(UserElo? elo, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Text(
            l10n.duelYourElo,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            elo != null ? '${elo.elo}' : '—',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (elo != null) ...[
            const SizedBox(height: 4),
            Text(
              l10n.duelRankStats(elo.rank, elo.wins, elo.losses, elo.draws),
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.duelHowItWorks,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _buildInfoRow(Icons.music_note_rounded, l10n.duelInfoSameSong),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.timer_rounded, l10n.duelInfoGuessEarly),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.expand_rounded, l10n.duelInfoExtendSnippet),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.emoji_events_rounded, l10n.duelInfoFiveRounds),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        ),
      ],
    );
  }

  Widget _buildFindMatchButton(AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: TextButton(
          onPressed: _onFindMatch,
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(
            l10n.duelFindMatch,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
