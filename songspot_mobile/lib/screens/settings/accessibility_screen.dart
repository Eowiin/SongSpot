import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/settings_provider.dart';

class AccessibilityScreen extends StatelessWidget {
  const AccessibilityScreen({super.key});

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
              // App bar
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
                      child: Text(
                        l10n.accessibilityTitle,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ── Text Size ─────────────────────────────────────────
                    _AccessibilitySection(
                      icon: Icons.text_fields,
                      title: l10n.accessibilityTextSize,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Live preview
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              l10n.accessibilityTextSizePreview,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                l10n.accessibilityTextSizeSmall,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              Expanded(
                                child: Slider(
                                  value: settings.textScaleFactor,
                                  min: 0.8,
                                  max: 1.6,
                                  divisions: 4,
                                  label: '${(settings.textScaleFactor * 100).round()}%',
                                  activeColor: AppTheme.primaryColor,
                                  onChanged: (v) => context.read<SettingsProvider>().setTextScaleFactor(v),
                                ),
                              ),
                              Text(
                                l10n.accessibilityTextSizeLarge,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Reduce Animations ─────────────────────────────────
                    _AccessibilitySection(
                      icon: Icons.animation,
                      title: l10n.accessibilityReduceAnimations,
                      child: SwitchListTile(
                        title: Text(
                          l10n.accessibilityReduceAnimationsSubtitle,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        value: settings.reduceAnimations,
                        onChanged: (v) => context.read<SettingsProvider>().setReduceAnimations(v),
                        activeThumbColor: AppTheme.primaryColor,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── High Contrast ─────────────────────────────────────
                    _AccessibilitySection(
                      icon: Icons.contrast,
                      title: l10n.accessibilityHighContrast,
                      child: SwitchListTile(
                        title: Text(
                          l10n.accessibilityHighContrastSubtitle,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        value: settings.highContrast,
                        onChanged: (v) => context.read<SettingsProvider>().setHighContrast(v),
                        activeThumbColor: AppTheme.primaryColor,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Color Blindness ───────────────────────────────────
                    _AccessibilitySection(
                      icon: Icons.palette_outlined,
                      title: l10n.accessibilityColorBlindness,
                      child: RadioGroup<ColorBlindnessMode>(
                        groupValue: settings.colorBlindnessMode,
                        onChanged: (v) {
                          if (v != null) {
                            context.read<SettingsProvider>().setColorBlindnessMode(v);
                          }
                        },
                        child: Column(
                          children: ColorBlindnessMode.values.map((mode) {
                            final label = switch (mode) {
                              ColorBlindnessMode.none => l10n.accessibilityColorBlindnessNone,
                              ColorBlindnessMode.deuteranopia => l10n.accessibilityColorBlindnessDeuteranopia,
                              ColorBlindnessMode.protanopia => l10n.accessibilityColorBlindnessProtanopia,
                              ColorBlindnessMode.tritanopia => l10n.accessibilityColorBlindnessTritanopia,
                            };
                            return RadioListTile<ColorBlindnessMode>(
                              title: Text(label, style: Theme.of(context).textTheme.bodyLarge),
                              value: mode,
                              contentPadding: EdgeInsets.zero,
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Enhanced Screen Reader ────────────────────────────
                    _AccessibilitySection(
                      icon: Icons.hearing,
                      title: l10n.accessibilityEnhancedScreenReader,
                      child: SwitchListTile(
                        title: Text(
                          l10n.accessibilityEnhancedScreenReaderSubtitle,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        value: settings.enhancedSemantics,
                        onChanged: (v) => context.read<SettingsProvider>().setEnhancedSemantics(v),
                        activeThumbColor: AppTheme.primaryColor,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccessibilitySection extends StatelessWidget {
  const _AccessibilitySection({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Row(
              children: [
                Icon(icon, color: AppTheme.primaryColor, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
