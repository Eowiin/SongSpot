import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/search_updates.dart';

class SearchStatusText extends StatelessWidget {
  const SearchStatusText({super.key, required this.status});
  final SearchStatus status;
  @override
  Widget build(BuildContext context) {
    if (status == SearchStatus.idle) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final text = switch (status) {
      SearchStatus.loading => l10n.searchLoading,
      SearchStatus.enriching => l10n.searchEnriching,
      SearchStatus.empty => l10n.searchEmpty,
      SearchStatus.unavailable => l10n.searchUnavailable,
      SearchStatus.refine => l10n.searchRefine,
      SearchStatus.idle => '',
    };
    // Capped because this line sits between the guess field and the button
    // under it when the box is pinned above the soft keyboard. The longest
    // message ("more results exist, add the artist…") runs to eight lines at
    // text scale 2 on a phone — 272px, more than the whole pinned box has —
    // and the field itself would be the thing pushed off the screen.
    return Padding(padding: const EdgeInsets.all(8),
      child: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall));
  }
}
