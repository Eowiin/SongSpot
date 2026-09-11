import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../providers/game_session_provider.dart';

/// How a difficulty is shown: its colour, its name in the player's language,
/// and what it changes.
extension DifficultyStyle on Difficulty {
  Color get color => switch (this) {
        Difficulty.easy => const Color(0xFF4CAF50),
        Difficulty.medium => const Color(0xFFFF9800),
        Difficulty.hard => const Color(0xFFE53935),
      };

  String localizedName(AppLocalizations l10n) => switch (this) {
        Difficulty.easy => l10n.soloDifficultyEasy,
        Difficulty.medium => l10n.soloDifficultyMedium,
        Difficulty.hard => l10n.soloDifficultyHard,
      };

  /// "5-second snippet · ×1.5": what picking this difficulty changes.
  String summary(AppLocalizations l10n) =>
      '${l10n.soloSnippetSeconds(snippetDuration.inSeconds)} · '
      '×${scoreMultiplier.toStringAsFixed(1)}';
}
