/// Shared bounded refresh policy for artist selection, solo and duel.
enum SearchStatus { idle, loading, enriching, empty, unavailable, refine }

class SearchPage {
  const SearchPage(this.results, {this.enrichment = 'idle', this.degraded = false, this.nextOffset, this.refineRequired = false});
  final List<dynamic> results;
  final String enrichment;
  final bool degraded;
  final int? nextOffset;
  final bool refineRequired;
  bool get pending => enrichment == 'pending' || enrichment == 'running';
  SearchStatus get status => pending ? SearchStatus.enriching
      : degraded || enrichment == 'failed' || enrichment == 'deferred' ? SearchStatus.unavailable
      : results.isEmpty ? SearchStatus.empty
      : (nextOffset != null || refineRequired) ? SearchStatus.refine : SearchStatus.idle;

  factory SearchPage.parse(dynamic data) {
    // A previously deployed server still responds with a list.
    if (data is List) return SearchPage(data);
    if (data is! Map || data['results'] is! List) {
      throw const FormatException('Invalid search response');
    }
    return SearchPage(data['results'] as List,
      enrichment: data['enrichment'] as String? ?? 'idle',
      degraded: data['degraded'] == true, nextOffset: data['next_offset'] as int?, refineRequired: data['refine_required'] == true);
  }
}

Stream<SearchPage> searchUpdates({
  required Future<SearchPage> Function() fetch,
  required bool Function() isActive,
  Future<void> Function(Duration)? wait,
}) async* {
  final pause = wait ?? Future<void>.delayed;
  for (var attempt = 0; attempt < 4 && isActive(); attempt++) {
    if (attempt > 0) {
      await pause(Duration(milliseconds: 600 * (1 << (attempt - 1))));
      if (!isActive()) return;
    }
    final page = await fetch();
    if (!isActive()) return;
    yield attempt == 3 && page.pending
        ? SearchPage(page.results, enrichment: 'deferred', nextOffset: page.nextOffset, refineRequired: page.refineRequired)
        : page;
    if (!page.pending) return;
  }
}
