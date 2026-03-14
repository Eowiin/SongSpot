import '../l10n/app_localizations.dart';

String dailyModeLocalizedLabel(AppLocalizations l10n, String mode) {
  switch (mode) {
    case 'genre':
      return l10n.dailyModeGenreLabel;
    case 'decade':
      return l10n.dailyModeDecadeLabel;
    case 'hardcore':
      return l10n.dailyModeHardcoreLabel;
    default:
      return l10n.dailyModeMixLabel;
  }
}

String dailyModeLocalizedSubtitle(
  AppLocalizations l10n,
  String mode, {
  String? laneName,
}) {
  if (laneName != null && laneName.isNotEmpty && mode != 'mix') {
    return l10n.dailyModeLaneSubtitle(laneName);
  }

  switch (mode) {
    case 'genre':
      return l10n.dailyModeGenreSubtitle;
    case 'decade':
      return l10n.dailyModeDecadeSubtitle;
    case 'hardcore':
      return l10n.dailyModeHardcoreSubtitle;
    default:
      return l10n.dailyModeMixSubtitle;
  }
}
