import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: isQueuing
                  ? _buildSearchingState(duel)
                  : _buildIdleState(duel),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIdleState(DuelProvider duel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 48),
        _buildEloCard(duel.elo),
        const SizedBox(height: 40),
        _buildInfoSection(),
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
        _buildFindMatchButton(),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildSearchingState(DuelProvider duel) {
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
        const Text(
          'Finding opponent...',
          style: TextStyle(
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
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
          ),
        ),
      ],
    ),
    );
  }

  Widget _buildEloCard(UserElo? elo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          const Text(
            'Your ELO',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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
              'Rank #${elo.rank}  •  ${elo.wins}W ${elo.losses}L ${elo.draws}D',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How it works',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _buildInfoRow(Icons.music_note_rounded, 'Same song, same round for both players'),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.timer_rounded, 'Guess early = more points (up to 100)'),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.expand_rounded, 'Extend snippet for more confidence, fewer points'),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.emoji_events_rounded, '5 rounds — highest score wins ELO'),
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

  Widget _buildFindMatchButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text(
            'Find Match',
            style: TextStyle(
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
