import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/settings_provider.dart';

class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  static const _locales = [
    (locale: Locale('en'), nativeName: 'English', flag: '🇬🇧'),
    (locale: Locale('fr'), nativeName: 'Français', flag: '🇫🇷'),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Semantics(
                      label: l10n.settingsBackLabel,
                      button: true,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new),
                        onPressed: () => Navigator.of(context).pop(),
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Flexible(
                      child: Text(l10n.languageTitle, style: Theme.of(context).textTheme.headlineMedium),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: _locales.map((entry) {
                    final isSelected = settings.locale.languageCode == entry.locale.languageCode;
                    return Semantics(
                      selected: isSelected,
                      button: true,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          gradient: AppTheme.cardGradient,
                          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                          border: isSelected
                              ? Border.all(color: AppTheme.primaryColor, width: 2)
                              : null,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => context.read<SettingsProvider>().setLocale(entry.locale),
                            borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Text(entry.flag, style: const TextStyle(fontSize: 24)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      entry.nativeName,
                                      style: Theme.of(context).textTheme.bodyLarge,
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(Icons.check_circle, color: AppTheme.primaryColor),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
