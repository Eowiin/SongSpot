import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

class CompactPlaybackPanel extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final String? caption;
  final String? durationLabel;
  final VoidCallback? onPressed;
  final bool isPlaying;
  final IconData idleIcon;

  const CompactPlaybackPanel({
    super.key,
    this.title,
    this.subtitle,
    this.caption,
    this.durationLabel,
    required this.onPressed,
    required this.isPlaying,
    this.idleIcon = Icons.play_arrow_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (title != null)
          Text(title!, style: Theme.of(context).textTheme.headlineSmall),
        if (subtitle != null) ...[
          SizedBox(height: title != null ? 6 : 0),
          Text(
            subtitle!,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: AppTheme.primaryColor),
            textAlign: TextAlign.center,
          ),
        ],
        if (caption != null) ...[
          const SizedBox(height: 6),
          Text(
            caption!,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 16),
        _PlaybackWaveform(isPlaying: isPlaying),
        const SizedBox(height: 14),
        _PlaybackControlButton(
          onPressed: onPressed,
          icon: isPlaying ? Icons.replay_rounded : idleIcon,
        ),
        if (durationLabel != null) ...[
          const SizedBox(height: 10),
          Text(
            durationLabel!,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: isPlaying ? AppTheme.accentColor : AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }
}

class _PlaybackControlButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;

  const _PlaybackControlButton({required this.onPressed, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

class _PlaybackWaveform extends StatefulWidget {
  final bool isPlaying;

  const _PlaybackWaveform({required this.isPlaying});

  @override
  State<_PlaybackWaveform> createState() => _PlaybackWaveformState();
}

class _PlaybackWaveformState extends State<_PlaybackWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  static const _barFactors = [0.35, 0.7, 0.5, 0.95, 0.55, 0.8, 0.4];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _PlaybackWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.isPlaying) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(_barFactors.length, (index) {
              final factor = _barFactors[index];
              final oscillation =
                  (math.sin((_controller.value * 2 * math.pi) + index) + 1) / 2;
              final activeHeight = 12 + (oscillation * 28 * factor);
              final idleHeight = 10 + (14 * factor);
              final height = widget.isPlaying ? activeHeight : idleHeight;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 6,
                height: height,
                decoration: BoxDecoration(
                  gradient: widget.isPlaying
                      ? AppTheme.primaryGradient
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppTheme.textSecondary.withValues(alpha: 0.8),
                            AppTheme.textSecondary.withValues(alpha: 0.35),
                          ],
                        ),
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
