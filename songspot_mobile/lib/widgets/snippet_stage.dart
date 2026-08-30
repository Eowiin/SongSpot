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
    required this.sounding,
    required this.loading,
    required this.onTap,
    this.width = 260,
  });

  final String label;
  final Duration snippetDuration;
  final bool playing;

  /// Whether the snippet is actually coming out of the speaker. The rail runs
  /// off this rather than [playing], which is already true while the player
  /// buffers: a rail started at the tap ends that much before the sound does,
  /// which on a 1s snippet is most of the bar.
  final bool sounding;

  final bool loading;
  final VoidCallback? onTap;

  final double width;

  @override
  State<SnippetButton> createState() => _SnippetButtonState();
}

class _SnippetButtonState extends State<SnippetButton> {
  @override
  Widget build(BuildContext context) {
    final busy = widget.playing || widget.loading;

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
        SnippetProgressRail(
          duration: widget.snippetDuration,
          sounding: widget.sounding,
          width: widget.width,
        ),
      ],
    );
  }
}

/// The thin line under a play button that runs the length of the snippet.
///
/// It is driven by [sounding] — the audio actually coming out of the speaker —
/// rather than by the tap that asked for it, so a player who has waited a
/// moment for the audio to buffer does not watch the rail finish early.
class SnippetProgressRail extends StatefulWidget {
  const SnippetProgressRail({
    super.key,
    required this.duration,
    required this.sounding,
    this.width = 260,
  });

  /// How long the snippet lasts — the time the rail takes to cross.
  final Duration duration;

  /// Whether the snippet is sounding right now. The rail runs while this is
  /// true and sits empty the rest of the time.
  final bool sounding;

  final double width;

  @override
  State<SnippetProgressRail> createState() => _SnippetProgressRailState();
}

class _SnippetProgressRailState extends State<SnippetProgressRail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rail = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    // The duel rebuilds this widget mid-round, so a rail that comes into
    // being while the snippet is already sounding has to pick it up.
    if (widget.sounding) _rail.forward(from: 0);
  }

  @override
  void didUpdateWidget(SnippetProgressRail old) {
    super.didUpdateWidget(old);
    if (widget.duration != old.duration) {
      _rail.duration = widget.duration;
    }
    if (widget.sounding != old.sounding) {
      if (widget.sounding) {
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
    // With animations off the rail cannot tell the story, so it simply sits
    // full while the snippet plays.
    final animate = !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

    return SizedBox(
      width: widget.width,
      height: 2,
      child: AnimatedBuilder(
        animation: _rail,
        builder: (context, _) {
          final value = !widget.sounding
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
    );
  }
}
