import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/file_saver.dart';
import '../../widgets/gradient_button.dart';
import '../auth/login_screen.dart';

class MyDataScreen extends StatefulWidget {
  const MyDataScreen({super.key, this.showDeleteSection = false});

  /// When true, the page scrolls to the delete section automatically.
  final bool showDeleteSection;

  @override
  State<MyDataScreen> createState() => _MyDataScreenState();
}

class _MyDataScreenState extends State<MyDataScreen> {
  final _deleteScrollController = ScrollController();
  final _exportButtonKey = GlobalKey();
  bool _isExporting = false;
  bool _isDeleting = false;
  String? _exportError;
  String? _deleteError;

  @override
  void initState() {
    super.initState();
    if (widget.showDeleteSection) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _deleteScrollController.animateTo(
          _deleteScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _deleteScrollController.dispose();
    super.dispose();
  }

  Future<void> _handleExport() async {
    setState(() {
      _isExporting = true;
      _exportError = null;
    });

    try {
      final apiService = ApiService();
      final payload = await apiService.exportData();
      // The user may leave while the request is in flight. Do not open a
      // share sheet for a screen that has already been closed.
      if (!mounted) return;
      // The endpoint returns decoded JSON, so re-encode it before saving.
      final bytes = utf8.encode(
        const JsonEncoder.withIndent('  ').convert(payload),
      );

      await saveBytesAsFile(
        bytes: bytes,
        fileName: 'songspot_data.json',
        mimeType: 'application/json',
        subject: 'SongSpot — My data export',
        origin: _exportButtonRect(),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _exportError = e.message);
    } catch (e) {
      if (mounted) setState(() => _exportError = e.toString());
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// The export button's rect in global coordinates, for anchoring the iOS
  /// share sheet. Falls back to a point at the centre of the screen: iOS only
  /// needs a non-empty rect inside the view, and a missing one is a crash.
  Rect _exportButtonRect() {
    final box = _exportButtonKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize && !box.size.isEmpty) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    final center = MediaQuery.sizeOf(context).center(Offset.zero);
    return Rect.fromCenter(center: center, width: 1, height: 1);
  }

  Future<void> _handleDelete() async {
    final l10n = AppLocalizations.of(context);
    final password = await _showDeleteConfirmDialog();
    if (password == null || !mounted) return;

    if (password.isEmpty) {
      setState(() => _deleteError = l10n.fieldRequired);
      return;
    }

    setState(() {
      _isDeleting = true;
      _deleteError = null;
    });

    try {
      final apiService = ApiService();
      await apiService.deleteAccount(password: password);

      if (!mounted) return;
      await context.read<AuthProvider>().logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } on ApiException catch (e) {
      setState(() => _deleteError = e.message);
    } catch (e) {
      setState(() => _deleteError = e.toString());
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<String?> _showDeleteConfirmDialog() {
    return showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

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
                      child: Text(l10n.myDataTitle, style: Theme.of(context).textTheme.headlineMedium),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: _deleteScrollController,
                  padding: AppTheme.pagePadding,
                  children: [
                    // ── Export ─────────────────────────────────────────
                    if (!widget.showDeleteSection)
                      _DataSection(
                        icon: Icons.download_outlined,
                        iconColor: AppTheme.accentColor,
                        title: l10n.myDataExportTitle,
                        description: l10n.myDataExportDescription,
                        errorMessage: _exportError,
                        child: GradientButton(
                          key: _exportButtonKey,
                          text: l10n.myDataExportButton,
                          onPressed: _handleExport,
                          isLoading: _isExporting,
                        ),
                      ),
                    if (!widget.showDeleteSection) const SizedBox(height: 24),

                    // ── Delete ─────────────────────────────────────────
                    _DataSection(
                      icon: Icons.delete_forever_outlined,
                      iconColor: AppTheme.errorColor,
                      title: l10n.myDataDeleteTitle,
                      description: l10n.myDataDeleteDescription,
                      errorMessage: _deleteError,
                      child: OutlinedButton.icon(
                        onPressed: _isDeleting ? null : _handleDelete,
                        icon: _isDeleting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.errorColor),
                                ),
                              )
                            : const Icon(Icons.delete_forever, color: AppTheme.errorColor),
                        label: Text(
                          l10n.myDataDeleteButton,
                          style: const TextStyle(color: AppTheme.errorColor),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.errorColor),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.borderRadius),
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
    );
  }
}

class _DataSection extends StatelessWidget {
  const _DataSection({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.child,
    this.errorMessage,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final Widget child;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(width: 10),
              Flexible(
                child: Text(title, style: Theme.of(context).textTheme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
          if (errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              errorMessage!,
              style: const TextStyle(color: AppTheme.errorColor),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      backgroundColor: AppTheme.surfaceColor,
      title: Text(l10n.myDataDeleteConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.myDataDeleteConfirmMessage),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            obscureText: true,
            // No AutofillGroup around this one on purpose: the manager should
            // offer the stored password, but never prompt to save from a
            // delete-account dialog.
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              hintText: l10n.changePasswordCurrent,
              filled: true,
              fillColor: AppTheme.backgroundColor,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => TextButton(
            onPressed: value.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, value.text.trim()),
            child: Text(
              l10n.myDataDeleteConfirmButton,
              style: const TextStyle(color: AppTheme.errorColor),
            ),
          ),
        ),
      ],
    );
  }
}
