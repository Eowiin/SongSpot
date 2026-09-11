import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';

/// The shortest report the server accepts: about the least that can describe
/// a problem at all.
const int _minLength = 10;
const int _maxLength = 2000;

/// Ask the player what went wrong, and send it to the developer.
///
/// The app version, platform and language are attached automatically, so the
/// player only has to describe the problem. Resolves to true once the report
/// has been sent, so the caller can thank them.
Future<bool?> showBugReportDialog(
  BuildContext context, {
  required bool isGuest,
  required String appVersion,
  required String locale,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _BugReportDialog(
      isGuest: isGuest,
      appVersion: appVersion,
      locale: locale,
    ),
  );
}

class _BugReportDialog extends StatefulWidget {
  const _BugReportDialog({
    required this.isGuest,
    required this.appVersion,
    required this.locale,
  });

  final bool isGuest;
  final String appVersion;
  final String locale;

  @override
  State<_BugReportDialog> createState() => _BugReportDialogState();
}

class _BugReportDialogState extends State<_BugReportDialog> {
  final TextEditingController _message = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Rebuild as the player types, so Send enables once the text is long
    // enough.
    _message.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  bool get _canSend => !_sending && _message.text.trim().length >= _minLength;

  String get _platform => kIsWeb ? 'web' : defaultTargetPlatform.name;

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ApiService().reportBug(
        message: _message.text.trim(),
        asGuest: widget.isGuest,
        appVersion: widget.appVersion.isEmpty ? null : widget.appVersion,
        platform: _platform,
        locale: widget.locale,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = AppLocalizations.of(context).bugReportFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      backgroundColor: AppTheme.surfaceColor,
      scrollable: true,
      title: Text(l10n.bugReportTitle),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.bugReportIntro, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _message,
              autofocus: true,
              enabled: !_sending,
              minLines: 5,
              maxLines: 8,
              maxLength: _maxLength,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.bugReportHint,
                hintStyle: const TextStyle(color: AppTheme.textSecondary),
                filled: true,
                fillColor: AppTheme.backgroundColor,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppTheme.errorColor, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: _canSend ? _send : null,
          child: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.bugReportSend),
        ),
      ],
    );
  }
}
