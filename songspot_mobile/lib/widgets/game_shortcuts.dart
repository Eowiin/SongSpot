import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The keyboard for a round: Space or R replays the snippet, Enter advances
/// once the answer is out. Shared by the solo game and the duel, which had the
/// same wiring and the same bug in it.
///
/// The hard part is that the guess box holds focus for most of a round on a
/// pointer layout — it is focused the moment a track loads, so the player can
/// type without reaching for the mouse. A shortcut that only fired while
/// [hostFocus] held focus therefore fired never.
///
/// So Space is live inside the guess box too, but only while that box is
/// empty: that is exactly when the player wants another listen, and never a
/// moment a space belongs in a title. As soon as there is text to append a
/// space to, Space is a space again.
///
/// R gets no such licence. It is a plausible first letter of a title, and the
/// player would lose the R of "Roxanne" to the snippet.
///
/// A disabled action reports the key as unhandled, so it falls through to the
/// text field, or activates whichever button the player has tabbed to.
class GameShortcuts extends StatefulWidget {
  const GameShortcuts({
    super.key,
    required this.hostFocus,
    required this.guessFocus,
    required this.guessController,
    required this.canReplay,
    required this.onReplay,
    required this.child,
    this.canAdvance,
    this.onAdvance,
  });

  /// Holds focus whenever the guess box does not, so the shortcuts still have
  /// somewhere to be heard. Autofocused.
  final FocusNode hostFocus;

  final FocusNode guessFocus;
  final TextEditingController guessController;

  /// Whether replaying is possible at all right now — nothing is playing, no
  /// track is loading, the round is live.
  final bool Function() canReplay;

  final VoidCallback onReplay;

  /// Omit both to leave Enter alone, as the duel does: there is nothing to
  /// advance to.
  final bool Function()? canAdvance;
  final VoidCallback? onAdvance;

  final Widget child;

  @override
  State<GameShortcuts> createState() => _GameShortcutsState();
}

class _GameShortcutsState extends State<GameShortcuts> {
  /// The scope this subtree lives in, captured so the focus listener never has
  /// to look it up mid-notification.
  FocusScopeNode? _scope;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_reclaimDroppedFocus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = FocusScope.of(context);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_reclaimDroppedFocus);
    super.dispose();
  }

  /// Takes focus back when a click drops it on the floor.
  ///
  /// Clicking the play button takes focus off the guess box and hands it to
  /// nobody — on a desktop browser a text field gives up focus on any tap
  /// outside it. The enclosing scope ends up holding it, and key events then
  /// stop reaching this subtree at all: no shortcut here can fire, whatever it
  /// is allowed to do, and the keyboard is dead for the rest of the round.
  ///
  /// The round never belongs to the scope, so the host takes focus back.
  ///
  /// Only this subtree's own scope counts. A dialog or the next route brings
  /// its own, and pulling focus out of one of those would be a worse bug than
  /// the one being fixed.
  void _reclaimDroppedFocus() {
    if (!mounted) return;
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null || !identical(focused, _scope)) return;
    widget.hostFocus.requestFocus();
  }

  /// Whether a shortcut may fire given where the focus currently is.
  ///
  /// Anything else focused — the give-up button, a result row — keeps the key:
  /// Space presses whatever the player has tabbed to, which is what they are
  /// asking for.
  bool _reachable(bool fromEmptyGuessBox) {
    if (widget.hostFocus.hasPrimaryFocus) return true;
    return fromEmptyGuessBox &&
        widget.guessFocus.hasPrimaryFocus &&
        widget.guessController.text.isEmpty;
  }

  /// Replays, then sweeps up after the key.
  ///
  /// Handling a key event asks the platform not to type it, but that request
  /// is not honoured everywhere. A guess box left holding nothing but a space
  /// would quietly disarm Space for the rest of the round, so clear it once
  /// the frame has settled — leading whitespace is never a guess anyway.
  void _replayAndKeepBoxClean() {
    widget.onReplay();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final text = widget.guessController.text;
      if (text.isNotEmpty && text.trim().isEmpty) {
        widget.guessController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.space):
            ReplaySnippetIntent(fromEmptyGuessBox: true),
        SingleActivator(LogicalKeyboardKey.keyR): ReplaySnippetIntent(),
        SingleActivator(LogicalKeyboardKey.enter): AdvanceRoundIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): AdvanceRoundIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ReplaySnippetIntent: _GameShortcutAction<ReplaySnippetIntent>(
            enabled: (intent) =>
                _reachable(intent.fromEmptyGuessBox) && widget.canReplay(),
            onInvoke: _replayAndKeepBoxClean,
          ),
          AdvanceRoundIntent: _GameShortcutAction<AdvanceRoundIntent>(
            // Enter picks a result inside the guess box; it only advances the
            // round from the host, which takes focus back on the reveal.
            enabled: (_) =>
                widget.hostFocus.hasPrimaryFocus &&
                (widget.canAdvance?.call() ?? false),
            onInvoke: () => widget.onAdvance?.call(),
          ),
        },
        child: Focus(
          focusNode: widget.hostFocus,
          autofocus: true,
          child: widget.child,
        ),
      ),
    );
  }
}

class ReplaySnippetIntent extends Intent {
  const ReplaySnippetIntent({this.fromEmptyGuessBox = false});

  /// True for keys that may also fire from inside an empty guess box.
  final bool fromEmptyGuessBox;
}

class AdvanceRoundIntent extends Intent {
  const AdvanceRoundIntent();
}

class _GameShortcutAction<T extends Intent> extends Action<T> {
  _GameShortcutAction({required this.enabled, required this.onInvoke});

  final bool Function(T intent) enabled;
  final VoidCallback onInvoke;

  @override
  bool isEnabled(T intent, [BuildContext? context]) => enabled(intent);

  @override
  Object? invoke(T intent) {
    onInvoke();
    return null;
  }
}
