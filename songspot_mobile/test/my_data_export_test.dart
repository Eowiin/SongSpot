import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:songspot_mobile/l10n/app_localizations.dart';
import 'package:songspot_mobile/screens/settings/my_data_screen.dart';
import 'package:songspot_mobile/widgets/gradient_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=https://example.test/api');
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  for (final succeeds in [false, true]) {
    testWidgets(
      'export ${succeeds ? 'success' : 'failure'} after leaving screen',
      (tester) async {
        final response = Completer<http.Response>();
        var requests = 0;
        var fileOperations = 0;
        const channel = MethodChannel('plugins.flutter.io/path_provider');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            fileOperations++;
            throw PlatformException(code: 'unexpected_file_operation');
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
        });

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const MyDataScreen(),
          ),
        );

        // Invoke the same callback as a tap in a zone with a delayed HTTP client.
        http.runWithClient(
          () => tester
              .widget<GradientButton>(find.byType(GradientButton))
              .onPressed!(),
          () => MockClient((request) {
            requests++;
            expect(request.url.path, '/api/auth/data/export/');
            return response.future;
          }),
        );
        await tester.pump();
        expect(requests, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        response.complete(
          http.Response(
            succeeds ? '{"profile":{}}' : '{"error":"Export failed"}',
            succeeds ? 200 : 500,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(fileOperations, 0);
      },
    );
  }
}
