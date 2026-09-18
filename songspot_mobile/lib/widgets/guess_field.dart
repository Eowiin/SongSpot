import '../services/search_updates.dart';
import 'search_status_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../config/app_theme.dart';
import '../models/track.dart';

/// The search box and its result list, shared by the solo game and the duel.
///
/// It exists because guessing is the one thing the player does over and over,
/// and in a browser that means the keyboard: type, arrow down to the right
/// track, Enter. Before this, the only way to pick a result was to take a hand
/// off the keyboard and click it.
///
/// * `↑` / `↓` move the highlight, `Enter` picks it, `Esc` clears the box.
/// * The highlighted row scrolls itself into view.
/// * Rows show a pointer cursor and a hover state.
///
/// [resultsBelow] puts the list under the field, which is what a desktop
/// dropdown does. On a phone the list goes above, because the field is pinned
/// just over the soft keyboard and a list below it would be off-screen.
class GuessField extends StatefulWidget {
  const GuessField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.results,
    required this.onChanged,
    required this.onSelected,
    required this.hintText,
    this.keyboardHint,
    this.isSearching = false,
    this.searchStatus = SearchStatus.idle,
    this.resultsBelow = false,
    this.autofocus = false,
    this.onClear,
    this.maxResultsHeight = 260,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<Track> results;
  final ValueChanged<String> onChanged;
  final ValueChanged<Track> onSelected;
  final String hintText;

  /// One-line reminder of the shortcuts, shown under the field on pointer
  /// layouts. Null hides it.
  final String? keyboardHint;

  final bool isSearching;
  final SearchStatus searchStatus;
  final bool resultsBelow;
  final bool autofocus;
  final VoidCallback? onClear;
  final double maxResultsHeight;

  @override
  State<GuessField> createState() => _GuessFieldState();
}

class _GuessFieldState extends State<GuessField> {
  static const double _rowHeight = 56;

  final ScrollController _scrollController = ScrollController();
  int _highlighted = 0;

  /// The query the visible list was last reset for. See [didUpdateWidget].
  late String _query = widget.controller.text;

  @override
  void didUpdateWidget(GuessField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only a *new query* starts the highlight at the top again.
    //
    // One query is answered more than once: the server sends a first page and
    // then an enriched one 0.6s to 4s later (see `searchUpdates`). Comparing
    // the list identity reset on every arrival, so a player scrolling the
    // suggestions was thrown back to the first row seconds after they began
    // reading.
    if (widget.controller.text != _query) {
      _query = widget.controller.text;
      _highlighted = 0;
      _jumpToTopAfterFrame();
    } else if (_highlighted >= widget.results.length) {
      // A refreshed page can be shorter than the one being read.
      _highlighted = widget.results.isEmpty ? 0 : widget.results.length - 1;
    }
  }

  /// Sends the list back to the top once the current frame is done.
  ///
  /// Not straight away: the screen rebuilds this box from inside a
  /// [LayoutBuilder], so `didUpdateWidget` can run during layout, and
  /// `jumpTo` dispatches a scroll notification synchronously. The app bar
  /// listens for those and would call `setState` in the middle of a build.
  void _jumpToTopAfterFrame() {
    if (!_scrollController.hasClients || _scrollController.offset == 0) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  double get _scaledRowHeight =>
      _rowHeight * MediaQuery.textScalerOf(context).scale(14) / 14;

  void _move(int delta) {
    if (widget.results.isEmpty) return;
    setState(() {
      _highlighted =
          (_highlighted + delta).clamp(0, widget.results.length - 1);
    });
    _revealHighlighted();
  }

  void _revealHighlighted() {
    if (!_scrollController.hasClients) return;
    final row = _scaledRowHeight;
    final top = _highlighted * row;
    final viewport = _scrollController.position.viewportDimension;
    final offset = _scrollController.offset;
    final double target;
    if (top < offset) {
      target = top;
    } else if (top + row > offset + viewport) {
      target = top + row - viewport;
    } else {
      return;
    }
    _scrollController.jumpTo(
      target.clamp(0, _scrollController.position.maxScrollExtent),
    );
  }

  /// True where the only keyboard is the on-screen one, web included — a
  /// phone browser reports its OS, not `TargetPlatform.web`.
  bool get _touchOnly =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  void _submitHighlighted() {
    if (widget.results.isEmpty) return;
    final index = _highlighted.clamp(0, widget.results.length - 1);
    widget.onSelected(widget.results[index]);
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    // The list is the part that gives way when there is not enough room.
    //
    // Where the parent bounds the height — the phone layout, which pins this
    // box above the soft keyboard — the list is a flex child and takes what is
    // left once the field, its status line and whatever sits under them have
    // had theirs. Sizing it from a constant instead is what let the status
    // line ("adding more songs…") push the give-up button off a short screen:
    // that line is only there while a search runs, so the budget was right
    // exactly when nothing was happening.
    //
    // In the wide layout the box lives in a scroll view, so the height is
    // unbounded and a flex child would assert. There the list keeps its
    // natural height, capped by [maxResultsHeight], and the page scrolls.
    return LayoutBuilder(
      builder: (context, constraints) {
        final field = _buildField(context);
        Widget results = widget.results.isEmpty
            ? const SizedBox.shrink()
            : _buildResults(context);
        if (constraints.maxHeight.isFinite) {
          results = Flexible(child: results);
        }
        final status = SearchStatusText(status: widget.searchStatus);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: widget.resultsBelow
              ? [field, status, const SizedBox(height: 8), results]
              : [results, status, const SizedBox(height: 8), field],
        );
      },
    );
  }

  Widget _buildField(BuildContext context) {
    // Bound nearer than the app-level text editing shortcuts, so the arrow
    // keys drive the list instead of the caret while results are showing.
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowUp): _MoveHighlightIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowDown): _MoveHighlightIntent(1),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _MoveHighlightIntent: _MoveHighlightAction(
            onMove: _move,
            enabled: () => widget.results.isNotEmpty,
          ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              _clear();
              return null;
            },
          ),
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: const TextStyle(color: AppTheme.ink3),
                prefixIcon:
                    const Icon(Icons.search_rounded, color: AppTheme.ink3),
                suffixIcon: _buildSuffix(),
                filled: true,
                fillColor: AppTheme.surfaceColor,
              ),
              onChanged: widget.onChanged,
              onSubmitted: (_) {
                // On a phone the "search" key means "I have finished typing",
                // not "take whatever is first": a player still reading the
                // list had a song submitted for them. Put the keyboard away
                // and leave the suggestions up to be tapped. A physical
                // keyboard keeps Enter as the pick, which is what the
                // highlight and the shortcut hint are there for.
                if (_touchOnly) {
                  widget.focusNode.unfocus();
                  return;
                }
                _submitHighlighted();
              },
            ),
            if (widget.keyboardHint != null) ...[
              const SizedBox(height: 6),
              Text(
                widget.keyboardHint!,
                style: AppTheme.kicker(color: AppTheme.ink3, size: 9.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget? _buildSuffix() {
    if (widget.isSearching) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.primaryColor,
          ),
        ),
      );
    }
    if (widget.controller.text.isEmpty) return null;
    return IconButton(
      icon: const Icon(Icons.clear_rounded, color: AppTheme.ink3),
      tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
      onPressed: _clear,
    );
  }

  Widget _buildResults(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: widget.maxResultsHeight),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(AppTheme.borderRadius),
        border: Border.all(color: AppTheme.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        controller: _scrollController,
        child: ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemExtent: _scaledRowHeight,
          itemCount: widget.results.length.clamp(0, 40),
          itemBuilder: (context, i) => _GuessResultRow(
            track: widget.results[i],
            highlighted: i == _highlighted,
            onTap: () => widget.onSelected(widget.results[i]),
            onHover: () {
              if (_highlighted != i) setState(() => _highlighted = i);
            },
          ),
        ),
      ),
    );
  }
}

class _MoveHighlightIntent extends Intent {
  const _MoveHighlightIntent(this.delta);
  final int delta;
}

/// Disabled while there is nothing to navigate, so the arrow keys fall through
/// to the text field and still move the caret.
class _MoveHighlightAction extends Action<_MoveHighlightIntent> {
  _MoveHighlightAction({required this.onMove, required this.enabled});

  final void Function(int delta) onMove;
  final bool Function() enabled;

  @override
  bool isEnabled(_MoveHighlightIntent intent, [BuildContext? context]) =>
      enabled();

  @override
  Object? invoke(_MoveHighlightIntent intent) {
    onMove(intent.delta);
    return null;
  }
}

class _GuessResultRow extends StatelessWidget {
  const _GuessResultRow({
    required this.track,
    required this.highlighted,
    required this.onTap,
    required this.onHover,
  });

  final Track track;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final active = highlighted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: active
                ? AppTheme.primaryColor.withValues(alpha: 0.16)
                : Colors.transparent,
            border: const Border(
              bottom: BorderSide(color: AppTheme.line),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              // The accent bar marks the row Enter would pick.
              Container(
                width: 3,
                height: 34,
                color: active ? AppTheme.accentColor : Colors.transparent,
              ),
              const SizedBox(width: 10),
              _Cover(url: track.coverUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.ink3,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.keyboard_return_rounded,
                      size: 14, color: AppTheme.accentColor),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const placeholder = SizedBox(
      width: 36,
      height: 36,
      child: ColoredBox(
        color: AppTheme.backgroundDeep,
        child: Icon(Icons.music_note_rounded,
            size: 16, color: AppTheme.primaryColor),
      ),
    );
    if (url == null) return placeholder;
    return Image.network(
      url!,
      width: 36,
      height: 36,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}
