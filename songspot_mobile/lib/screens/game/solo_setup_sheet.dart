import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../config/difficulty_style.dart';
import '../../config/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/category.dart';
import '../../models/solo_setup.dart';
import '../../providers/game_session_provider.dart';
import '../../services/storage_service.dart';
import '../../widgets/pressable.dart';
import 'game_screen.dart';
import 'style_picker_screen.dart';

/// The solo panel: how hard, which style, then play.
///
/// Every solo run starts here, from the home screen and from the end of a run.
/// The panel is deliberately short: three controls and nothing else. The
/// first version showed every category, the artist search and the three
/// difficulties at once, so a player who only wanted to play had to read
/// through fifteen options first. Difficulty is the one choice every run
/// needs, so it stays in the panel. The style is a single row showing the
/// current choice, and the full list is one tap away on its own screen. The
/// panel opens on the last run's settings, so playing again takes one tap.
///
/// A bottom sheet on a phone. A wide viewport gets a centred dialog instead,
/// because a sheet there is a full-width strip far from the pointer.
Future<SoloSetup?> showSoloSetupSheet(BuildContext context, SoloSetup initial) {
  if (context.isWide) {
    return showDialog<SoloSetup>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.surfaceColor,
        insetPadding: const EdgeInsets.all(32),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
          side: const BorderSide(color: AppTheme.line),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: _SoloSetupPanel(initial: initial, sheet: false),
        ),
      ),
    );
  }
  return showModalBottomSheet<SoloSetup>(
    context: context,
    backgroundColor: AppTheme.surfaceColor,
    // Without these the sheet is capped at 9/16 of the screen and painted
    // under the system navigation bar, which can push the play button out of
    // reach at large text sizes.
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppTheme.cardBorderRadius)),
    ),
    builder: (ctx) => _SoloSetupPanel(initial: initial, sheet: true),
  );
}

/// Start a run with [setup], and remember it as the next run's starting point.
Future<void> startSoloRun(
  BuildContext context,
  SoloSetup setup, {
  bool replace = false,
}) async {
  final navigator = Navigator.of(context);
  await StorageService().saveSoloSetup(setup.toJson());
  final route = MaterialPageRoute<void>(
    builder: (_) => GameScreen(
      mix: setup.isMix,
      category: setup.category,
      artistFilter: setup.artistName,
      artistDeezerId: setup.artistDeezerId,
      difficulty: setup.difficulty,
    ),
  );
  if (replace) {
    navigator.pushReplacement(route);
  } else {
    navigator.push(route);
  }
}

class _SoloSetupPanel extends StatefulWidget {
  const _SoloSetupPanel({required this.initial, required this.sheet});

  final SoloSetup initial;
  final bool sheet;

  @override
  State<_SoloSetupPanel> createState() => _SoloSetupPanelState();
}

class _SoloSetupPanelState extends State<_SoloSetupPanel> {
  late SoloSetup _setup = widget.initial;

  /// Requested once, as soon as the panel opens. The style screen is handed
  /// this same request rather than firing its own: two at once used to race
  /// each other through a token refresh, and the loser showed only a retry
  /// button.
  late final Future<List<Category>> _categories = fetchStockedCategories();

  @override
  void initState() {
    super.initState();
    _checkRememberedCategory();
  }

  /// A remembered category may no longer be stocked. If so, the panel falls
  /// back to every genre rather than start a run that would end on its first
  /// round.
  Future<void> _checkRememberedCategory() async {
    final remembered = _setup.category;
    try {
      final categories = await _categories;
      if (!mounted || remembered == null || _setup.category?.id != remembered.id) return;
      final current = categories.where((c) => c.id == remembered.id).firstOrNull;
      setState(() {
        _setup = current == null ? _setup.withMix() : _setup.withCategory(current);
      });
    } catch (_) {
      // The style screen shows the failure and offers a retry. Here it only
      // means the remembered category goes unchecked.
    }
  }

  Future<void> _pickStyle() async {
    final picked = await Navigator.of(context).push<SoloSetup>(
      MaterialPageRoute(
        builder: (_) => StylePickerScreen(current: _setup, categories: _categories),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _setup = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      child: Padding(
        padding: widget.sheet
            ? EdgeInsets.fromLTRB(24, 20, 24, 24 + MediaQuery.viewPaddingOf(context).bottom)
            : const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.sheet) ...[
              Center(
                child: Container(width: 36, height: 4, color: AppTheme.lineStrong),
              ),
              const SizedBox(height: 20),
            ],
            Text(l10n.homeSoloLabel.toUpperCase(), style: AppTheme.display(24)),
            const SizedBox(height: 24),
            SectionLabel(l10n.categoryDifficulty),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final difficulty in Difficulty.values) ...[
                  if (difficulty != Difficulty.values.first) const SizedBox(width: 8),
                  Expanded(child: _difficultyButton(l10n, difficulty)),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _setup.difficulty.summary(l10n),
              style: const TextStyle(color: AppTheme.ink3, fontSize: 12),
            ),
            const SizedBox(height: 20),
            _styleRow(l10n),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, _setup),
                child: Text(l10n.homePlay.toUpperCase()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _difficultyButton(AppLocalizations l10n, Difficulty difficulty) {
    final selected = _setup.difficulty == difficulty;
    final color = difficulty.color;
    return Pressable(
      onTap: () => setState(() => _setup = _setup.withDifficulty(difficulty)),
      borderRadius: AppTheme.borderRadius,
      lift: 0,
      semanticLabel: difficulty.localizedName(l10n),
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: hovered ? 0.08 : 0.04),
          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
          border: Border.all(
            color: selected ? color : AppTheme.line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            difficulty.localizedName(l10n).toUpperCase(),
            maxLines: 1,
            style: AppTheme.action(
              size: 13,
              color: selected ? AppTheme.textPrimary : AppTheme.ink2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _styleRow(AppLocalizations l10n) {
    final value = _setup.category?.name ?? _setup.artistName ?? l10n.mixLabel;
    return Pressable(
      onTap: _pickStyle,
      borderRadius: AppTheme.borderRadius,
      lift: 0,
      semanticLabel: '${l10n.soloStyle}: $value',
      builder: (context, hovered) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: hovered ? 0.08 : 0.04),
          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
          border: Border.all(color: hovered ? AppTheme.lineStrong : AppTheme.line),
        ),
        child: Row(
          children: [
            Text(l10n.soloStyle, style: const TextStyle(color: AppTheme.ink3, fontSize: 14)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.action(size: 14),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.ink3, size: 20),
          ],
        ),
      ),
    );
  }
}
