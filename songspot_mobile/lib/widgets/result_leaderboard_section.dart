import 'package:flutter/material.dart';

import '../config/app_theme.dart';

class ResultLeaderboardRowData {
  final String title;
  final String subtitle;
  final String scoreText;

  const ResultLeaderboardRowData({
    required this.title,
    required this.subtitle,
    required this.scoreText,
  });
}

class ResultLeaderboardSection extends StatelessWidget {
  final String title;
  final String emptyText;
  final List<ResultLeaderboardRowData> rows;

  const ResultLeaderboardSection({
    super.key,
    required this.title,
    required this.emptyText,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        if (rows.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
            ),
            child: Text(
              emptyText,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          )
        else
          ...rows.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            final rank = index + 1;

            Color rankColor;
            if (rank == 1) {
              rankColor = const Color(0xFFFFD700);
            } else if (rank == 2) {
              rankColor = const Color(0xFFC0C0C0);
            } else if (rank == 3) {
              rankColor = const Color(0xFFCD7F32);
            } else {
              rankColor = AppTheme.textSecondary;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: rankColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: rankColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          row.subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      row.scoreText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
