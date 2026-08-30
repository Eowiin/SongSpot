import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/widgets/game_shortcuts.dart';

/// The round is played with one hand on the keyboard: Space to hear the
/// snippet again, then the title, then Enter. The guess box holds focus for
/// nearly all of that, so these tests are mostly about which keys are allowed
/// to reach past it — and which must fall through and be typed.
void main() {
  late FocusNode hostFocus;
  late FocusNode guessFocus;
  late TextEditingController guessController;
  late int replays;
  late int advances;
  late bool canReplay;
  late bool canAdvance;

  setUp(() {
    hostFocus = FocusNode(debugLabel: 'host');
    guessFocus = FocusNode(debugLabel: 'guess');
    guessController = TextEditingController();
    replays = 0;
    advances = 0;
    canReplay = true;
    canAdvance = false;
  });

  tearDown(() {
    hostFocus.dispose();
    guessFocus.dispose();
    guessController.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameShortcuts(
            hostFocus: hostFocus,
            guessFocus: guessFocus,
            guessController: guessController,
            canReplay: () => canReplay,
            onReplay: () => replays++,
            canAdvance: () => canAdvance,
            onAdvance: () => advances++,
            child: TextField(
              controller: guessController,
              focusNode: guessFocus,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Focus the guess box the way the game does when a track loads.
  Future<void> focusGuessBox(WidgetTester tester, {String text = ''}) async {
    guessController.text = text;
    guessFocus.requestFocus();
    await tester.pump();
    expect(guessFocus.hasPrimaryFocus, isTrue);
  }

  group('replay', () {
    testWidgets('Space replays while the host holds focus', (tester) async {
      await pump(tester);
      expect(hostFocus.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(replays, 1);
    });

    testWidgets('Space replays from an empty guess box', (tester) async {
      await pump(tester);
      await focusGuessBox(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(replays, 1,
          reason: 'the box is focused for the whole guessing phase, so a '
              'host-only shortcut would never fire');
    });

    testWidgets('Space is a space again once the box has text',
        (tester) async {
      await pump(tester);
      await focusGuessBox(tester, text: 'bohemian');

      final handled = await simulateKeyDownEvent(LogicalKeyboardKey.space);
      expect(replays, 0);
      expect(handled, isFalse,
          reason: 'the key must fall through to the text field');
      await simulateKeyUpEvent(LogicalKeyboardKey.space);
    });

    testWidgets('R replays from the host but never from the guess box',
        (tester) async {
      await pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      expect(replays, 1);

      // "Roxanne" must keep its R.
      await focusGuessBox(tester);
      final handled = await simulateKeyDownEvent(LogicalKeyboardKey.keyR);
      expect(replays, 1);
      expect(handled, isFalse);
      await simulateKeyUpEvent(LogicalKeyboardKey.keyR);
    });

    testWidgets('Space still replays after a click drops the focus',
        (tester) async {
      await pump(tester);
      await focusGuessBox(tester);

      // What clicking the play button does on a desktop browser: the guess box
      // gives up focus and nothing takes it. Left there, the scope holds focus
      // and key events never reach these shortcuts again.
      guessFocus.unfocus();
      await tester.pump();
      expect(hostFocus.hasPrimaryFocus, isTrue,
          reason: 'the host must take dropped focus back');

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      expect(replays, 2, reason: 'a click must not disarm the keyboard');
    });

    testWidgets('nothing replays while the snippet is already playing',
        (tester) async {
      canReplay = false;
      await pump(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      expect(replays, 0);
    });

    testWidgets('a stray space left in the box does not disarm the shortcut',
        (tester) async {
      await pump(tester);
      await focusGuessBox(tester);

      // Whatever the platform does with the key it was asked not to type.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      guessController.text = ' ';
      await tester.pump();
      expect(guessController.text, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(replays, 2);
    });
  });

  group('advance', () {
    testWidgets('Enter advances once the answer is out', (tester) async {
      await pump(tester);
      canAdvance = true;

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(advances, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      expect(advances, 2);
    });

    testWidgets('Enter does not advance while the answer is still hidden',
        (tester) async {
      await pump(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(advances, 0);
    });

    testWidgets('Enter in the guess box picks a result, it does not advance',
        (tester) async {
      await pump(tester);
      canAdvance = true;
      await focusGuessBox(tester, text: 'bohemian');

      final handled = await simulateKeyDownEvent(LogicalKeyboardKey.enter);
      expect(advances, 0);
      expect(handled, isFalse,
          reason: 'Enter belongs to the result list while the box has focus');
      await simulateKeyUpEvent(LogicalKeyboardKey.enter);
    });
  });
}
