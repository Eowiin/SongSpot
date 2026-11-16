import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../services/app_update_service.dart';
import '../widgets/gradient_button.dart';

/// Shown instead of the app when the installed version is behind the store.
///
/// There is deliberately no way past it: no back navigation, no "later". The
/// only action opens the store page.
class UpdateRequiredScreen extends StatelessWidget {
  final RequiredUpdate update;

  const UpdateRequiredScreen({super.key, required this.update});

  Future<void> _openStore() async {
    await launchUrl(Uri.parse(update.storeUrl), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.system_update_rounded,
                    size: 64,
                    color: AppTheme.accentColor,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.updateRequiredTitle,
                    style: AppTheme.display(24),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.updateRequiredBody,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  GradientButton(
                    text: l10n.updateRequiredButton,
                    onPressed: _openStore,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
