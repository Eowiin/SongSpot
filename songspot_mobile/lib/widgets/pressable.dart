import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// A tappable surface that behaves the way a browser user expects a control to
/// behave: pointer cursor, a small lift on hover, a focus ring, and
/// Enter/Space activation.
///
/// The app was written for touch, where a bare [GestureDetector] is enough. In
/// a browser that same widget gives no cursor change and no hover feedback, so
/// half the home screen reads as decoration rather than as buttons. Everything
/// clickable goes through this instead.
///
/// [builder] is called with the current hover state for surfaces that want to
/// restyle themselves (brighten a border, reveal an arrow); [child] is the
/// shorthand when the lift alone is enough.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    this.child,
    this.builder,
    required this.onTap,
    this.borderRadius = AppTheme.borderRadius,
    this.lift = 2,
    this.semanticLabel,
    this.hoverCursor = SystemMouseCursors.click,
  }) : assert(child != null || builder != null,
            'Pressable needs either a child or a builder');

  final Widget? child;
  final Widget Function(BuildContext context, bool hovered)? builder;
  final VoidCallback? onTap;
  final double borderRadius;

  /// Pixels the surface rises on hover. The marketing site's buttons use 2px;
  /// larger tiles can afford 3–4.
  final double lift;

  final String? semanticLabel;
  final MouseCursor hoverCursor;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value || !mounted) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final radius = BorderRadius.circular(widget.borderRadius);
    // Honours the accessibility "reduce animations" switch, which the app
    // pipes into MediaQuery from SettingsProvider.
    final animate = !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    final hovered = enabled && _hovered;

    Widget content = widget.builder != null
        ? widget.builder!(context, hovered)
        : widget.child!;

    content = Material(
      type: MaterialType.transparency,
      borderRadius: radius,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: radius,
        // The lift is the hover feedback; a splash under an opaque card would
        // never be seen anyway.
        hoverColor: Colors.transparent,
        focusColor: Colors.white.withValues(alpha: 0.06),
        child: content,
      ),
    );

    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: enabled ? widget.hoverCursor : MouseCursor.defer,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: AnimatedContainer(
          transform: Matrix4.translationValues(0, hovered ? -widget.lift : 0, 0),
          duration: Duration(milliseconds: animate ? 140 : 0),
          curve: Curves.easeOut,
          child: content,
        ),
      ),
    );
  }
}

/// The spaced-out uppercase label that opens a section — the site's `.kicker`.
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.color = AppTheme.accentColor,
    this.icon,
  });

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text.toUpperCase(),
      style: AppTheme.kicker(color: color),
    );
    if (icon == null) return label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Flexible(child: label),
      ],
    );
  }
}

/// A block with the accent rule across its top — the site's `.col--rule`.
/// Replaces the app's glow-and-radius cards so the two read as one product.
class RuledPanel extends StatelessWidget {
  const RuledPanel({
    super.key,
    required this.child,
    this.accent = AppTheme.accentColor,
    this.padding = const EdgeInsets.all(20),
    this.background,
  });

  final Widget child;
  final Color accent;
  final EdgeInsetsGeometry padding;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    // The accent rule is a child rather than a BorderSide: BoxDecoration only
    // accepts a uniform border alongside a borderRadius.
    return Container(
      decoration: BoxDecoration(
        color: background ?? AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
        border: Border.all(color: AppTheme.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 2, color: accent),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}
