import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/l10n/app_localizations.dart';
import 'package:songspot_mobile/services/search_updates.dart';
import 'package:songspot_mobile/widgets/search_status_text.dart';

void main() {
  testWidgets('empty, enrichment and failure have distinct visible messages', (tester) async {
    Future<void> show(SearchStatus status) => tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SearchStatusText(status: status)),
    ));
    await show(SearchStatus.empty);
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucun résultat'), findsOneWidget);
    await show(SearchStatus.enriching);
    await tester.pumpAndSettle();
    expect(find.textContaining('résultats supplémentaires'), findsOneWidget);
    expect(find.textContaining('Aucun résultat'), findsNothing);
    await show(SearchStatus.unavailable);
    await tester.pumpAndSettle();
    expect(find.textContaining('temporairement indisponible'), findsOneWidget);
  });
}
