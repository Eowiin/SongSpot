import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/l10n/app_localizations.dart';
import 'package:songspot_mobile/providers/game_session_provider.dart';
import 'package:songspot_mobile/screens/game/session_end_screen.dart';
import 'package:songspot_mobile/widgets/gradient_button.dart';

/// The in-app accessibility slider goes up to 160%, and it replaces the system
/// scaler outright (see main.dart), so every layout has to survive 1.6.
const _scales = [1.0, 1.2, 1.4, 1.6];

Widget _host(Widget child, double scale, Locale locale) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
      ),
      child: child!,
    ),
    home: child,
  );
}

void main() {
  // 320dp wide is the narrowest phone the app realistically runs on.
  const narrow = Size(320, 640);

  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  group('GradientButton', () {
    for (final scale in _scales) {
      testWidgets('no overflow at ${(scale * 100).round()}%', (tester) async {
        tester.view.physicalSize = narrow;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_host(
          const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                // Deliberately long: the German/French labels are the ones
                // that used to wrap past the old fixed 56px height.
                child: GradientButton(text: 'Commencer une nouvelle partie'),
              ),
            ),
          ),
          scale,
          const Locale('fr'),
        ));

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('SessionEndScreen', () {
    for (final scale in _scales) {
      for (final locale in const [Locale('en'), Locale('es'), Locale('fr')]) {
        testWidgets(
            'no overflow at ${(scale * 100).round()}% (${locale.languageCode})',
            (tester) async {
          tester.view.physicalSize = narrow;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(_host(
            const SessionEndScreen(
              songsPlayed: 12,
              songsCorrect: 9,
              bestStreak: 5,
              totalScore: 12450,
              difficulty: Difficulty.hard,
            ),
            scale,
            locale,
          ));
          await tester.pump();

          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
