import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:songspot_mobile/services/analytics_service.dart';

/// The consent gate is the part with legal consequences, and it is the one
/// piece of AnalyticsService that works without a live Firebase app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AnalyticsService().resetForTest();
    SharedPreferences.setMockInitialValues({});
  });

  test('collection is opt-in: the default is off', () {
    // Compliance-relevant: flipping this back to true makes the app collect
    // before consent in the EU. Assert the value, not the constant.
    expect(AnalyticsService.defaultEnabled, isFalse);
  });

  test('defaults to the declared default when nothing is stored', () async {
    await AnalyticsService().initialize();

    expect(AnalyticsService().isEnabled, AnalyticsService.defaultEnabled);
  });

  test('setEnabled persists under the key SettingsProvider reads', () async {
    await AnalyticsService().setEnabled(false);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AnalyticsService.prefsKeyEnabled), isFalse);
    expect(AnalyticsService().isEnabled, isFalse);
  });

  test('opting out silences events instead of throwing', () async {
    await AnalyticsService().setEnabled(false);

    // No Firebase app in tests, so this also covers the uninitialized path:
    // analytics must never surface as an error in the game.
    await expectLater(
      AnalyticsService().sessionStarted(
        mode: 'solo',
        genre: 'pop',
        difficulty: 'hard',
      ),
      completes,
    );
  });
}
