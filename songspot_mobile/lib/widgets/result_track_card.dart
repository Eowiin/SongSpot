import 'package:flutter/material.dart';

import '../config/app_theme.dart';

class ResultTrackCard extends StatelessWidget {
  final String title;
  final String artist;
  final String? coverUrl;
  final double artworkSize;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onArtworkTap;
  final bool isArtworkPlaying;
  final Widget? footer;

  const ResultTrackCard({
    super.key,
    required this.title,
    required this.artist,
    this.coverUrl,
    this.artworkSize = 200,
    this.padding = const EdgeInsets.all(24),
    this.onArtworkTap,
    this.isArtworkPlaying = false,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final artwork = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: coverUrl != null
          ? Image.network(
              coverUrl!,
              width: artworkSize,
              height: artworkSize,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _FallbackArtwork(size: artworkSize),
            )
          : _FallbackArtwork(size: artworkSize),
    );

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
      ),
      child: Column(
        children: [
          if (onArtworkTap == null)
            artwork
          else
            GestureDetector(
              onTap: onArtworkTap,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  artwork,
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isArtworkPlaying
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            artist,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
          if (footer != null) ...[const SizedBox(height: 16), footer!],
        ],
      ),
    );
  }
}

class _FallbackArtwork extends StatelessWidget {
  final double size;

  const _FallbackArtwork({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: AppTheme.surfaceColor,
      child: Icon(Icons.album, size: size * 0.42, color: AppTheme.primaryColor),
    );
  }
}
