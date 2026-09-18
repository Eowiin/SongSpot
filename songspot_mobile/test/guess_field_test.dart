import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/config/app_theme.dart';
import 'package:songspot_mobile/models/track.dart';
import 'package:songspot_mobile/widgets/guess_field.dart';

/// The browser client is played with the keyboard, so these are the shortcuts
/// the game depends on: arrows move the highlight, Enter picks it, Escape
/// clears the box.
void main() {
  const results = [
    Track(id: '1', title: 'Alpha', artist: 'A'),
    Track(id: '2', title: 'Beta', artist: 'B'),
    Track(id: '3', title: 'Gamma', artist: 'C'),
  ];

  late TextEditingController controller;
  late FocusNode focusNode;
  late List<Track> picked;

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode();
    picked = [];
  });

  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  /// Runs [body] as if on [platform].
  ///
  /// The override has to be undone inside the test body — the framework checks
  /// it before `tearDown` runs. Tests default to Android, where the field
  /// answers the keyboard's action key differently on purpose.
  Future<void> on(TargetPlatform platform, Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<void> pump(
    WidgetTester tester, {
    List<Track> options = results,
    bool resultsBelow = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: GuessField(
              controller: controller,
              focusNode: focusNode,
              results: options,
              resultsBelow: resultsBelow,
              autofocus: true,
              hintText: 'Guess',
              onChanged: (_) {},
              onSelected: picked.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Enter picks the first result by default', (tester) async {
    await on(TargetPlatform.macOS, () async {
      await pump(tester);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      expect(picked.single.title, 'Alpha');
    });
  });

  testWidgets('arrow down moves the highlight before Enter picks',
      (tester) async {
    await on(TargetPlatform.macOS, () async {
      await pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      expect(picked.single.title, 'Gamma');
    });
  });

  testWidgets('arrow up stops at the top of the list', (tester) async {
    await on(TargetPlatform.macOS, () async {
      await pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
      }
      await tester.testTextInput.receiveAction(TextInputAction.search);
      expect(picked.single.title, 'Alpha');
    });
  });

  testWidgets('arrow down stops at the bottom of the list', (tester) async {
    await on(TargetPlatform.macOS, () async {
      await pump(tester);
      for (var i = 0; i < 8; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      await tester.testTextInput.receiveAction(TextInputAction.search);
      expect(picked.single.title, 'Gamma');
    });
  });

  testWidgets('Escape clears the field', (tester) async {
    await pump(tester);
    controller.text = 'alph';
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(controller.text, isEmpty);
  });

  testWidgets('Enter with no results picks nothing', (tester) async {
    await on(TargetPlatform.macOS, () async {
      await pump(tester, options: const []);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      expect(picked, isEmpty);
    });
  });

  testWidgets('tapping a result picks it', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Beta'));
    await tester.pump();
    expect(picked.single.title, 'Beta');
  });

  testWidgets('the phone keyboard closes the search instead of picking',
      (tester) async {
    // Validating on a soft keyboard means "I have finished typing", not "take
    // the first suggestion": it used to submit a song for a player who was
    // still reading the list.
    await on(TargetPlatform.android, () async {
      await pump(tester);
      expect(focusNode.hasFocus, isTrue);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(picked, isEmpty, reason: 'nothing is guessed for the player');
      expect(focusNode.hasFocus, isFalse, reason: 'the keyboard goes away');
      expect(find.text('Alpha'), findsOneWidget,
          reason: 'the suggestions stay up to be tapped');
    });
  });

  testWidgets('a refreshed page for the same query keeps the scroll position',
      (tester) async {
    // A query is answered twice: a first page, then an enriched one up to four
    // seconds later. Scrolling the suggestions used to be undone by that
    // second arrival.
    final many = List.generate(
      40,
      (i) => Track(id: '$i', title: 'Song $i', artist: 'Artist $i'),
    );
    controller.text = 'song';
    await pump(tester, options: many);

    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pump();
    final scrolled = tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position
        .pixels;
    expect(scrolled, greaterThan(0));

    // Same query, a fresh list instance — an enriched page landing.
    await pump(tester, options: [...many]);
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable).last).position.pixels,
      scrolled,
      reason: 'an enriched page must not throw the reader back to the top',
    );

    // A new query does start again from the top.
    controller.text = 'song t';
    await pump(tester, options: [...many]);
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable).last).position.pixels,
      0,
    );
  });

  testWidgets('the list sits below the field on a pointer layout',
      (tester) async {
    await pump(tester);
    final fieldY = tester.getTopLeft(find.byType(TextField)).dy;
    final listY = tester.getTopLeft(find.text('Alpha')).dy;
    expect(listY, greaterThan(fieldY));
  });

  testWidgets('the list sits above the field on a phone layout',
      (tester) async {
    await pump(tester, resultsBelow: false);
    final fieldY = tester.getTopLeft(find.byType(TextField)).dy;
    final listY = tester.getTopLeft(find.text('Alpha')).dy;
    expect(listY, lessThan(fieldY));
  });
}
