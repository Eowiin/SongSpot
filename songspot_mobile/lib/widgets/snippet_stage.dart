import 'dart:ui';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'pressable.dart';

/// The blurred artwork bled across the page behind the stage.
///
/// It is the cover of the track being guessed, blurred far past recognition —
/// it gives the screen the colour of the song without giving the song away.
class CoverBackdrop extends StatelessWidget {
  const CoverBackdrop({super.key, this.coverUrl});

  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    if (coverUrl == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
            child: Opacity(
              opacity: 0.42,
              child: Image.network(
                coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The square cover card at the centre of the guessing screen.
///
/// [reveal] runs 0 → 1 as the answer is given away: the blur lifts with it, so
/// the artwork sharpening into place *is* the reveal.
class CoverStage extends StatelessWidget {
  const CoverStage({
    super.key,
    required this.coverUrl,
    required this.reveal,
    required this.size,
    this.loading = false,
  });

  final String? coverUrl;
  final double reveal;
  final double size;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final blur = (1 - reveal) * 26.0;
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.backgroundDeep,
          borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
          border: Border.all(color: AppTheme.lineStrong),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (coverUrl != null)
                Image.network(
                  coverUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _NoCover(),
                )
              else
                const _NoCover(),
              if (blur > 0.5)
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  child: ColoredBox(
                    color: AppTheme.backgroundDeep.withValues(alpha: 0.25),
                  ),
                ),
              if (loading)
                ColoredBox(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoCover extends StatelessWidget {
  const _NoCover();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppTheme.surfaceColor,
      child: Icon(Icons.music_note_rounded, color: AppTheme.ink3, size: 56),
    );
  }
}

/// The play control, with a rail underneath that fills over the length of the
/// snippet.
///
/// The rail is not decoration. On hard the snippet is one second long, so a
/// button that merely swapped its label for that second gave the player almost
/// nothing to see — and no way to tell a snippet that played from one that
/// silently failed. The rail draws the whole second.
class SnippetButton extends StatefulWidget {
  const SnippetButton({
    super.key,
    required this.label,
    required this.snippetDuration,
    required this.playing,
    required this.loading,
    required this.onTap,
    this.hint,
    this.width = 260,
  });

  final String label;
  final Duration snippetDuration;
  final bool playing;
  final bool loading;
  final VoidCallback? onTap;

  /// Keyboard reminder under the rail; null hides it.
  final String? hint;

  final double width;

  @override
  State<SnippetButton> createState() => _SnippetButtonState();
}

class _SnippetButtonState extends State<SnippetButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rail = AnimationController(
    vsync: this,
    duration: widget.snippetDuration,
  );

  @override
  void didUpdateWidget(SnippetButton old) {
    super.didUpdateWidget(old);
    if (widget.snippetDuration != old.snippetDuration) {
      _rail.duration = widget.snippetDuration;
    }
    if (widget.playing != old.playing) {
      if (widget.playing) {
        _rail.forward(from: 0);
      } else {
        _rail.stop();
        _rail.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _rail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.playing || widget.loading;
    // With animations off the rail cannot tell the story, so it simply sits
    // full while the snippet plays.
    final animate = !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Pressable(
          onTap: widget.onTap,
          borderRadius: AppTheme.borderRadius,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: widget.width,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              gradient: busy ? null : AppTheme.primaryGradient,
              color: busy ? AppTheme.surfaceColor : null,
              borderRadius: BorderRadius.circular(AppTheme.borderRadius),
              border: Border.all(
                color: busy ? AppTheme.lineStrong : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.loading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                else
                  Icon(
                    widget.playing
                        ? Icons.graphic_eq_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    widget.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.action(size: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: widget.width,
          height: 2,
          child: AnimatedBuilder(
            animation: _rail,
            builder: (context, _) {
              final value = !widget.playing
                  ? 0.0
                  : animate
                      ? _rail.value
                      : 1.0;
              return Align(
                alignment: Alignment.centerLeft,
                child: Stack(
                  children: [
                    Container(width: widget.width, color: AppTheme.line),
                    Container(
                      width: widget.width * value,
                      color: AppTheme.accentColor,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (widget.hint != null) ...[
          const SizedBox(height: 10),
          Text(
            widget.hint!,
            style: AppTheme.kicker(color: AppTheme.ink3, size: 9.5),
          ),
        ],
      ],
    );
  }
}
