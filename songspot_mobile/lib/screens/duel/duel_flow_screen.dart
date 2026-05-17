import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/duel_provider.dart';
import 'duel_game_screen.dart';
import 'duel_lobby_screen.dart';
import 'duel_result_screen.dart';

/// Single route that owns the DuelProvider for the entire duel session.
/// Switches between lobby / game / result widgets based on provider status.
class DuelFlowScreen extends StatelessWidget {
  const DuelFlowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DuelProvider(),
      child: Consumer<DuelProvider>(
        builder: (context, duel, _) {
          return switch (duel.status) {
            DuelStatus.idle ||
            DuelStatus.queuing ||
            DuelStatus.error =>
              const DuelLobbyScreen(),
            DuelStatus.matched ||
            DuelStatus.playing ||
            DuelStatus.roundReveal =>
              const DuelGameScreen(),
            DuelStatus.finished => const DuelResultScreen(),
          };
        },
      ),
    );
  }
}
