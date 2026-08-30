import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/config/app_theme.dart';
import 'package:songspot_mobile/config/responsive.dart';
import 'package:songspot_mobile/models/track.dart';
import 'package:songspot_mobile/widgets/guess_field.dart';

/// The wide game stage centres its column in the window *and* holds a guess
/// box whose results are a scrollable list. Those two requirements collided:
/// centring through [IntrinsicHeight] measured the subtree, the result list
/// is a shrink-wrapping viewport and cannot be measured, and the whole stage
/// stopped painting the moment the player typed anything.
void main() {
  const results = [
    Track(id: '1', title: 'Alpha', artist: 'A'),
    Track(id: '2', title: 'Beta', artist: 'B'),
  ];

  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode();
  });

  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  /// The wide stage, reduced to what makes it break: a centred column with a
  /// fixed-height stand-in for the artwork and the real guess field under it.
  Future<void> pumpStage(
    WidgetTester tester, {
    required List<Track> options,
    double height = 800,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 1200,
              height: height,
              child: FullHeightScroll(
                maxWidth: 620,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(key: Key('stage-top'), height: 300),
                    GuessField(
                      controller: controller,
                      focusNode: focusNode,
                      results: options,
                      resultsBelow: true,
                      hintText: 'Guess',
                      onChanged: (_) {},
                      onSelected: (_) {},
                    ),
                    const SizedBox(key: Key('stage-bottom'), height: 60),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the stage survives the result list appearing', (tester) async {
    await pumpStage(tester, options: const []);
    expect(tester.takeException(), isNull);

    // What typing does: results arrive, and a ListView joins the subtree.
    await pumpStage(tester, options: results);
    expect(tester.takeException(), isNull,
        reason: 'the guess results must not be measured for intrinsic height');

    // Still on screen, not merely exception-free.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.byKey(const Key('stage-top')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('stage-top'))).height, 300);
  });

  testWidgets('a tall window centres the stage instead of topping it out',
      (tester) async {
    await pumpStage(tester, options: const []);

    final viewport = tester.getRect(find.byType(FullHeightScroll));
    final above =
        tester.getTopLeft(find.byKey(const Key('stage-top'))).dy - viewport.top;
    final below = viewport.bottom -
        tester.getBottomLeft(find.byKey(const Key('stage-bottom'))).dy;
    expect(above, greaterThan(0), reason: 'dead band above, not only below');
    expect(above, closeTo(below, 1),
        reason: 'equal space above and below the stage');
  });

  testWidgets('a short window scrolls instead of overflowing', (tester) async {
    await pumpStage(tester, options: results, height: 300);
    expect(tester.takeException(), isNull);

    expect(find.byKey(const Key('stage-top')), findsOneWidget);
    await tester.drag(
        find.byType(FullHeightScroll), const Offset(0, -200));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
