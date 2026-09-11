import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_theme.dart';
import '../../config/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../auth/login_screen.dart';
import 'accessibility_screen.dart';
import 'bug_report_dialog.dart';
import 'change_email_screen.dart';
import 'change_password_screen.dart';
import 'language_screen.dart';
import 'my_data_screen.dart';

const _kPrivacyPath = '/privacy';
const _kTermsPath = '/terms';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = '';

  String _buildLegalUrl(String path) {
    final baseUrl = dotenv.get('SERVER_URL').trim();
    final normalizedBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$normalizedBase$path';
  }

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = '${info.version} (${info.buildNumber})';
      });
    }
  }

  Future<void> _handleLogout() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text(l10n.logoutConfirmTitle),
        content: Text(l10n.logoutConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.logout,
              style: const TextStyle(color: AppTheme.errorColor),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<AuthProvider>().logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _openBugReport() async {
    final sent = await showBugReportDialog(
      context,
      isGuest: context.read<AuthProvider>().isGuest,
      appVersion: _appVersion,
      locale: context.read<SettingsProvider>().locale.languageCode,
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).bugReportThanks)),
      );
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.settingsCouldNotOpenLink)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.watch<SettingsProvider>();
    final isGuest = context.watch<AuthProvider>().isGuest;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: ResponsiveCenter(
            maxWidth: 760,
            padding: EdgeInsets.symmetric(horizontal: context.pageGutter * 0.5),
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
                        l10n.settingsTitle.toUpperCase(),
                        style: AppTheme.display(24),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  children: [
                    // ── Account (authenticated only) ──────────────────────
                    if (!isGuest) ...[
                      _SectionHeader(l10n.settingsSectionAccount),
                      _SettingsTile(
                        icon: Icons.email_outlined,
                        title: l10n.settingsChangeEmail,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ChangeEmailScreen(),
                          ),
                        ),
                      ),
                      _SettingsTile(
                        icon: Icons.lock_outline,
                        title: l10n.settingsChangePassword,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ChangePasswordScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // ── Preferences ───────────────────────────────────────
                    // One header over the three rows that used to carry one
                    // each: "Accessibility" above a row reading
                    // "Accessibility" said the word twice and spent a gap
                    // saying it. The analytics consent lives here rather than
                    // under My Data because that section is hidden from
                    // guests, and the choice has to stay reachable for them.
                    _SectionHeader(l10n.settingsSectionPreferences),
                    _SettingsTile(
                      icon: Icons.accessibility_new_outlined,
                      title: l10n.settingsAccessibility,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AccessibilityScreen(),
                        ),
                      ),
                    ),
                    _SettingsTile(
                      icon: Icons.language_outlined,
                      title: l10n.settingsLanguage,
                      trailing: Text(
                        settings.locale.languageCode == 'fr'
                            ? 'Français'
                            : 'English',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LanguageScreen(),
                        ),
                      ),
                    ),
                    _SettingsSwitch(
                      icon: Icons.insights_outlined,
                      title: l10n.settingsAnalytics,
                      subtitle: l10n.settingsAnalyticsSubtitle,
                      value: settings.analyticsEnabled,
                      onChanged: (v) => settings.setAnalyticsEnabled(v),
                    ),
                    const SizedBox(height: 8),

                    // ── My Data (authenticated only) ───────────────────────
                    if (!isGuest) ...[
                      _SectionHeader(l10n.settingsSectionMyData),
                      _SettingsTile(
                        icon: Icons.download_outlined,
                        title: l10n.settingsExportData,
                        subtitle: l10n.settingsExportDataSubtitle,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const MyDataScreen()),
                        ),
                      ),
                      _SettingsTile(
                        icon: Icons.delete_outline,
                        title: l10n.settingsDeleteAccount,
                        subtitle: l10n.settingsDeleteAccountSubtitle,
                        iconColor: AppTheme.errorColor,
                        titleColor: AppTheme.errorColor,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const MyDataScreen(showDeleteSection: true),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // ── About ─────────────────────────────────────────────
                    _SectionHeader(l10n.settingsSectionAbout),
                    _SettingsTile(
                      icon: Icons.info_outline,
                      title: l10n.settingsAppVersion,
                      trailing: Text(
                        _appVersion,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      onTap: null,
                    ),
                    _SettingsTile(
                      icon: Icons.privacy_tip_outlined,
                      title: l10n.settingsPrivacyPolicy,
                      onTap: () => _openUrl(_buildLegalUrl(_kPrivacyPath)),
                    ),
                    _SettingsTile(
                      icon: Icons.article_outlined,
                      title: l10n.settingsTermsOfService,
                      onTap: () => _openUrl(_buildLegalUrl(_kTermsPath)),
                    ),
                    _SettingsTile(
                      icon: Icons.bug_report_outlined,
                      title: l10n.settingsReportBug,
                      onTap: _openBugReport,
                    ),
                    const SizedBox(height: 24),

                    // ── Sign in (guest) / Logout (authenticated) ──────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: isGuest
                          ? OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(
                                      builder: (_) => const LoginScreen()),
                                  (route) => false,
                                );
                              },
                              icon: const Icon(
                                Icons.login,
                                color: AppTheme.primaryColor,
                              ),
                              label: Text(
                                l10n.settingsSignInPrompt,
                                style: const TextStyle(color: AppTheme.primaryColor),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: AppTheme.primaryColor),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppTheme.borderRadius),
                                ),
                              ),
                            )
                          : OutlinedButton.icon(
                              onPressed: _handleLogout,
                              icon: const Icon(
                                Icons.logout,
                                color: AppTheme.errorColor,
                              ),
                              label: Text(
                                l10n.logout,
                                style:
                                    const TextStyle(color: AppTheme.errorColor),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: AppTheme.errorColor),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppTheme.borderRadius),
                                ),
                              ),
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
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: AppTheme.kicker()),
            const SizedBox(height: 8),
            const Divider(color: AppTheme.line, height: 1),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(AppTheme.borderRadius),
        border: Border.all(color: AppTheme.line),
      ),
      child: ListTile(
        leading: Icon(icon, color: iconColor ?? AppTheme.primaryColor),
        title: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: titleColor),
        ),
        subtitle: subtitle != null
            ? Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium)
            : null,
        trailing:
            trailing ??
            (onTap != null
                ? const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: AppTheme.textSecondary,
                  )
                : null),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
        ),
      ),
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(AppTheme.borderRadius),
        border: Border.all(color: AppTheme.line),
      ),
      child: SwitchListTile(
        secondary: Icon(icon, color: AppTheme.primaryColor),
        title: Text(title, style: Theme.of(context).textTheme.bodyLarge),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
        isThreeLine: subtitle != null,
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppTheme.primaryColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
        ),
      ),
    );
  }
}
