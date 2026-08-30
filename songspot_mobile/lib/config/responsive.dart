import 'package:flutter/widgets.dart';

/// Layout breakpoints, in logical pixels of the *viewport*.
///
/// The app ships one codebase for phones and the browser. Rather than
/// letterboxing the phone layout on a desktop, screens opt into a wider
/// arrangement above [wide] and keep the phone layout below it.
abstract final class Breakpoints {
  /// Above this the viewport is wide enough for side-by-side content.
  static const double wide = 900;

  /// Above this there is room for a third column of cards / more grid columns.
  static const double extraWide = 1300;
}

extension ResponsiveContext on BuildContext {
  double get viewportWidth => MediaQuery.sizeOf(this).width;

  /// True when there is room for a multi-column, desktop-style layout.
  bool get isWide => viewportWidth >= Breakpoints.wide;

  bool get isExtraWide => viewportWidth >= Breakpoints.extraWide;

  /// Horizontal page gutter — grows with the viewport so content does not
  /// sit flush against the window edge on a large screen.
  double get pageGutter {
    final width = viewportWidth;
    if (width >= Breakpoints.extraWide) return 48;
    if (width >= Breakpoints.wide) return 40;
    if (width >= 600) return 32;
    return 20;
  }
}

/// Centres [child] in a readable column and applies the page gutter.
///
/// Full-bleed backgrounds stay full-bleed — only the content is bounded, which
/// is what keeps a 2560px monitor from stretching a line of text across it.
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({
    super.key,
    required this.maxWidth,
    required this.child,
    this.padding,
  });

  /// Widest the content is allowed to get. Pick per screen: forms stay narrow,
  /// grids and dashboards can go wide.
  final double maxWidth;

  final Widget child;

  /// Overrides the adaptive horizontal gutter when a screen needs its own.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding:
              padding ?? EdgeInsets.symmetric(horizontal: context.pageGutter),
          child: child,
        ),
      ),
    );
  }
}

/// Number of grid columns for tiles that read best around [targetTileWidth].
int gridColumnsFor(double availableWidth, {double targetTileWidth = 260}) {
  final columns = (availableWidth / targetTileWidth).floor();
  return columns.clamp(2, 6);
}

/// Scrolls [child] while guaranteeing it at least the height of the viewport,
/// so a column with [MainAxisAlignment.center] really sits on the middle line
/// of a tall window and still scrolls in a short one.
///
/// The minimum height is imposed *inside* [ResponsiveCenter], not around it:
/// an [Align] loosens its child's constraints, so a minimum applied above one
/// never reaches the column.
///
/// Nothing here asks the subtree for intrinsic dimensions, and nothing may.
/// The guess result list is a shrink-wrapping viewport, which cannot answer
/// such a query — it throws, and the whole subtree stops painting. That rules
/// out both [IntrinsicHeight] and `SliverFillRemaining(hasScrollBody: false)`,
/// whose `performLayout` measures its child the same way.
///
/// The price is that [child] gets a minimum height but no maximum, so it can
/// hold no [Spacer] or [Expanded]. A column that needs one wants
/// [IntrinsicHeight] instead — and then may not contain a scrollable.
class FullHeightScroll extends StatelessWidget {
  const FullHeightScroll({
    super.key,
    required this.maxWidth,
    required this.child,
    this.padding,
  });

  /// Widest the content is allowed to get, as for [ResponsiveCenter].
  final double maxWidth;

  final Widget child;

  /// Overrides the adaptive horizontal gutter.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ResponsiveCenter(
          maxWidth: maxWidth,
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        ),
      ),
    );
  }
}
