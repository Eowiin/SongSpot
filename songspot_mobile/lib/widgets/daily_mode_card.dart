import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/room.dart';

class DailyModeCard extends StatelessWidget {
  final RoomDailyMode mode;
  final VoidCallback? onPlay;
  final VoidCallback? onContribute;

  const DailyModeCard({
    super.key,
    required this.mode,
    this.onPlay,
    this.onContribute,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _modeAccent(mode.mode);
    final progressMax = mode.costCoins <= 0 ? 1 : mode.costCoins;
    final progressValue = mode.progressCoins.clamp(0, progressMax).toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
        border: Border.all(
          color: accent.withValues(alpha: mode.isUnlocked ? 0.45 : 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_modeIcon(mode.mode), color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mode.subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                mode.isFree ? 'Free' : '${mode.costCoins} coins',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: mode.isUnlocked ? AppTheme.successColor : accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (!mode.isFree) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: progressValue / progressMax,
                color: accent,
                backgroundColor: AppTheme.surfaceColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              mode.isUnlocked
                  ? 'Unlocked for this room until next reset'
                  : '${mode.progressCoins}/${mode.costCoins} coins • ${mode.contributorCount} contributor${mode.contributorCount == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (onPlay != null)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onPlay,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      mode.isUnlocked || mode.isFree ? 'Play' : 'Preview',
                    ),
                  ),
                ),
              if (onPlay != null && onContribute != null)
                const SizedBox(width: 10),
              if (onContribute != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: mode.isUnlocked ? null : onContribute,
                    icon: const Icon(Icons.monetization_on_outlined),
                    label: Text(
                      mode.isUnlocked
                          ? 'Unlocked'
                          : mode.remainingCoins > 0
                          ? 'Contribute'
                          : 'Funded',
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

IconData _modeIcon(String mode) {
  switch (mode) {
    case 'genre':
      return Icons.graphic_eq;
    case 'decade':
      return Icons.history_edu;
    case 'hardcore':
      return Icons.whatshot;
    default:
      return Icons.shuffle;
  }
}

Color _modeAccent(String mode) {
  switch (mode) {
    case 'genre':
      return AppTheme.accentColor;
    case 'decade':
      return AppTheme.secondaryColor;
    case 'hardcore':
      return AppTheme.errorColor;
    default:
      return AppTheme.primaryColor;
  }
}
