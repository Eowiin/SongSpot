import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:songspot_mobile/l10n/app_localizations.dart';
import 'package:songspot_mobile/providers/auth_provider.dart';
import 'package:songspot_mobile/screens/auth/login_screen.dart';
import 'package:songspot_mobile/screens/auth/register_screen.dart';
import 'package:songspot_mobile/screens/settings/change_password_screen.dart';

/// Password managers only see a field if it carries `autofillHints`; without
/// them Flutter never registers the field with the Android autofill framework
/// and never sets `textContentType` on iOS. These tests pin that wiring down.

Widget _host(Widget child) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

/// These screens are laid out for real device fonts; under the test harness's
/// fallback font the auth rows overflow by a few pixels. That is not what is
/// under test here (text_scale_test.dart is the layout guard), so swallow only
/// overflow reports and let anything else fail the test.
Future<void> _pumpIgnoringOverflow(WidgetTester tester, Widget screen) async {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('A RenderFlex overflowed')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);

  await tester.pumpWidget(_host(screen));
  await tester.pump();
}

/// Every hint list found on the screen, in tree order.
List<List<String>> _hints(WidgetTester tester) {
  return tester
      .widgetList<EditableText>(find.byType(EditableText))
      .map((e) => (e.autofillHints ?? const <String>[]).toList())
      .toList();
}

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets('LoginScreen exposes username + password to autofill', (
    tester,
  ) async {
    await _pumpIgnoringOverflow(tester, const LoginScreen());

    expect(find.byType(AutofillGroup), findsOneWidget);
    expect(_hints(tester), [
      [AutofillHints.username, AutofillHints.email],
      [AutofillHints.password],
    ]);
  });

  testWidgets('RegisterScreen asks for a new password, not an existing one', (
    tester,
  ) async {
    await _pumpIgnoringOverflow(tester, const RegisterScreen());

    expect(find.byType(AutofillGroup), findsOneWidget);
    expect(_hints(tester), [
      [AutofillHints.username, AutofillHints.email],
      // The display name is deliberately unhinted: the login identifier is the
      // email, and hinting this field would make managers store the wrong one.
      <String>[],
      [AutofillHints.newPassword],
      [AutofillHints.newPassword],
    ]);
  });

  testWidgets('ChangePasswordScreen separates current from new', (
    tester,
  ) async {
    await _pumpIgnoringOverflow(tester, const ChangePasswordScreen());

    expect(find.byType(AutofillGroup), findsOneWidget);
    expect(_hints(tester), [
      [AutofillHints.password],
      [AutofillHints.newPassword],
      [AutofillHints.newPassword],
    ]);
  });
}
