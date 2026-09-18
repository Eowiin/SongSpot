import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/services/search_updates.dart';

void main() {
  test('legacy lists remain compatible', () {
    expect(SearchPage.parse([{'id': '1'}]).results.length, 1);
  });
  test('refresh is bounded and delivers enrichment without typing', () async {
    var calls = 0;
    final pages = await searchUpdates(fetch: () async {
      calls++;
      return SearchPage([calls], enrichment: 'pending');
    }, isActive: () => true, wait: (_) async {}).toList();
    expect(calls, 4);
    expect(pages.last.results, [4]);
  });
  test('late reply after query, round change or disposal is discarded', () async {
    var active = true;
    final pending = Completer<SearchPage>();
    final results = searchUpdates(fetch: () => pending.future,
      isActive: () => active).toList();
    await Future<void>.delayed(Duration.zero);
    active = false;
    pending.complete(const SearchPage([1]));
    expect(await results, isEmpty);
  });
  test('cancel during refresh delay prevents next request', () async {
    var active = true;
    var calls = 0;
    await searchUpdates(fetch: () async {
      calls++;
      return const SearchPage([], enrichment: 'running');
    }, isActive: () => active, wait: (_) async { active = false; }).toList();
    expect(calls, 1);
  });
  test('failure is distinct from empty and a new request can recover', () async {
    expect(const SearchPage([], enrichment: 'failed').status, SearchStatus.unavailable);
    expect(const SearchPage([]).status, SearchStatus.empty);
    await expectLater(searchUpdates(fetch: () async => throw Exception('offline'),
      isActive: () => true).toList(), throwsException);
    final pages = await searchUpdates(fetch: () async => const SearchPage([1]),
      isActive: () => true).toList();
    expect(pages.single.results, [1]);
  });
}
