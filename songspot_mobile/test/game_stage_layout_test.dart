import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/config/app_theme.dart';
import 'package:songspot_mobile/config/responsive.dart';
import 'package:songspot_mobile/l10n/app_localizations.dart';
import 'package:songspot_mobile/models/track.dart';
import 'package:songspot_mobile/services/search_updates.dart';
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

  // The phone layout pins the guess box and the give-up button under a
  // scrollable stage; see _buildNarrowGameBody in game_screen.dart. With the
  // soft keyboard up the body is only ~390pt tall, which is less than the
  // result list's natural height plus that chrome.
  Future<void> pumpPinnedStage(
    WidgetTester tester, {
    required List<Track> options,
    double height = 390,
    double scale = 1,
    SearchStatus status = SearchStatus.idle,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SizedBox(
              width: 411.4,
              height: height,
              child: LayoutBuilder(
                builder: (context, constraints) => Column(
                  children: [
                    const Expanded(
                      child: SingleChildScrollView(
                        child: SizedBox(key: Key('stage-top'), height: 600),
                      ),
                    ),
                    ConstrainedBox(
                      constraints:
                          BoxConstraints(maxHeight: constraints.maxHeight),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              child: GuessField(
                                controller: controller,
                                focusNode: focusNode,
                                results: options,
                                resultsBelow: false,
                                hintText: 'Guess',
                                searchStatus: status,
                                onChanged: (_) {},
                                onSelected: (_) {},
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: SizedBox(
                              key: const Key('stage-bottom'),
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () {},
                                child: const Text('GIVE UP'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

  testWidgets('the pinned guess box and its list fit above the keyboard',
      (tester) async {
    final many = List.generate(
      40,
      (i) => Track(id: '$i', title: 'Song $i', artist: 'Artist $i'),
    );

    for (final scale in [1.0, 1.3, 2.0]) {
      await pumpPinnedStage(tester, options: many, scale: scale);
      expect(tester.takeException(), isNull,
          reason: 'the result list must give way to the pinned controls '
              'at text scale $scale');
      expect(
        tester.getBottomLeft(find.byKey(const Key('stage-bottom'))).dy,
        lessThanOrEqualTo(390),
        reason: 'the give-up button stays on screen at text scale $scale',
      );
    }
  });

  testWidgets('the status line does not push the button off the screen',
      (tester) async {
    // The line under the field — "searching", "adding more songs", "no
    // match" — appears only while a search is running, so a budget worked out
    // for the field and the button alone overflowed the moment it showed up.
    final many = List.generate(
      40,
      (i) => Track(id: '$i', title: 'Song $i', artist: 'Artist $i'),
    );

    for (final status in [
      SearchStatus.loading,
      SearchStatus.enriching,
      SearchStatus.refine,
    ]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        await pumpPinnedStage(tester,
            options: many, scale: scale, status: status);
        expect(tester.takeException(), isNull,
            reason: 'no overflow with a $status line at text scale $scale');
        expect(
          tester.getBottomLeft(find.byKey(const Key('stage-bottom'))).dy,
          lessThanOrEqualTo(390),
          reason: 'the give-up button stays on screen with a $status line',
        );
      }
    }
  });

  testWidgets('a very short body keeps the button rather than the list',
      (tester) async {
    final many = List.generate(
      40,
      (i) => Track(id: '$i', title: 'Song $i', artist: 'Artist $i'),
    );
    await pumpPinnedStage(tester,
        options: many, height: 200, status: SearchStatus.enriching);
    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomLeft(find.byKey(const Key('stage-bottom'))).dy,
      lessThanOrEqualTo(200),
    );
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
