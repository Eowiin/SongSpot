import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../config/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/category.dart';
import '../../models/track.dart';
import '../../providers/auth_provider.dart';
import '../../providers/game_session_provider.dart';
import '../../widgets/game_shortcuts.dart';
import '../../widgets/guess_field.dart';
import '../../widgets/pressable.dart';
import '../../widgets/snippet_stage.dart';
import 'session_end_screen.dart';

class GameScreen extends StatefulWidget {
  final Category? category;
  final String? artistFilter;
  final Difficulty difficulty;

  const GameScreen({
    super.key,
    this.category,
    this.artistFilter,
    this.difficulty = Difficulty.medium,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _guessController = TextEditingController();
  final FocusNode _guessFocus = FocusNode();
  /// Holds keyboard focus whenever the guess box does not, so Space and Enter
  /// reach the shortcut handler instead of falling on the floor.
  final FocusNode _shortcutFocus = FocusNode(debugLabel: 'game shortcuts');
  late AnimationController _revealAnimController;
  late Animation<double> _revealAnim;
  // Cached to avoid context.read() in dispose() on a deactivated widget.
  GameSessionProvider? _provider;

  @override
  void initState() {
    super.initState();
    _revealAnimController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _revealAnim = CurvedAnimation(parent: _revealAnimController, curve: Curves.easeOut);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusGuessOnPointerLayout();
      _provider = context.read<GameSessionProvider>();
      _provider!.startSession(
        category: widget.category,
        artistFilter: widget.artistFilter,
        difficulty: widget.difficulty,
        isGuest: context.read<AuthProvider>().isGuest,
      );
      _provider!.loadNextSong();
      _provider!.addListener(_onProviderChanged);
    });
  }

  @override
  void dispose() {
    _provider?.removeListener(_onProviderChanged);
    _guessController.dispose();
    _guessFocus.dispose();
    _shortcutFocus.dispose();
    _revealAnimController.dispose();
    super.dispose();
  }

  void _onProviderChanged() {
    if (_provider?.endReason == SessionEndReason.poolCleared && mounted) {
      _endSession(reason: SessionEndReason.poolCleared);
    }
    if (_provider?.revealAnswer == true &&
        mounted &&
        _revealAnimController.status == AnimationStatus.dismissed) {
      _revealAnimController.forward();
      // Whatever was focused (the give-up button, say) is about to leave the
      // tree; take focus back so Enter still advances to the next song.
      _shortcutFocus.requestFocus();
    }
  }

  /// Puts the caret in the guess box so a desktop player can start typing the
  /// moment a track loads. Skipped on phones, where it would raise the soft
  /// keyboard over the artwork before the snippet has even played.
  ///
  /// Deferred by a frame: the shortcut host above the body autofocuses itself,
  /// and whichever request lands last wins.
  void _focusGuessOnPointerLayout() {
    if (!mounted || !context.isWide) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _guessFocus.requestFocus();
    });
  }

  Future<void> _nextSong() async {
    _revealAnimController.reset();
    _guessController.clear();
    _shortcutFocus.requestFocus();
    await _provider?.loadNextSong();
    _focusGuessOnPointerLayout();
  }

  Future<void> _endSession({SessionEndReason reason = SessionEndReason.quit}) async {
    _guessFocus.unfocus();
    final provider = _provider;
    if (provider == null) return;
    final score = await provider.endSession();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SessionEndScreen(
          score: score,
          songsPlayed: provider.songsPlayed,
          songsCorrect: provider.songsCorrect,
          bestStreak: provider.bestStreak,
          totalScore: provider.totalScore,
          category: widget.category,
          artistFilter: widget.artistFilter,
          difficulty: widget.difficulty,
          endReason: reason,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameSessionProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: _buildAppBar(provider),
          body: SafeArea(
            child: _withGameShortcuts(
              provider,
              provider.isLoadingTrack && provider.currentTrack == null
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primaryColor))
                  : provider.trackError != null && provider.currentTrack == null
                      ? _buildError(provider)
                      : _buildGameBody(context, provider),
            ),
          ),
        );
      },
    );
  }

  /// See [GameShortcuts] for why Space is live inside an empty guess box.
  Widget _withGameShortcuts(GameSessionProvider provider, Widget child) {
    return GameShortcuts(
      hostFocus: _shortcutFocus,
      guessFocus: _guessFocus,
      guessController: _guessController,
      canReplay: () => !provider.isPlaying && !provider.isLoadingTrack,
      onReplay: provider.replaySnippet,
      canAdvance: () => provider.revealAnswer && !provider.isLoadingTrack,
      onAdvance: () {
        if (provider.endReason == SessionEndReason.outOfLives) {
          _endSession(reason: SessionEndReason.outOfLives);
        } else {
          _nextSong();
        }
      },
      child: child,
    );
  }

  AppBar _buildAppBar(GameSessionProvider provider) {
    final l10n = AppLocalizations.of(context);
    return AppBar(
      backgroundColor: AppTheme.backgroundColor,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: AppTheme.surfaceColor,
              title: Text(l10n.gameEndSessionTitle,
                  style: const TextStyle(color: AppTheme.textPrimary)),
              content: Text(l10n.gameEndSessionMessage,
                  style: const TextStyle(color: AppTheme.textSecondary)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.cancel,
                      style: const TextStyle(color: AppTheme.textSecondary)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(l10n.gameEndSessionConfirm,
                      style: const TextStyle(color: AppTheme.primaryColor)),
                ),
              ],
            ),
          );
          if (confirmed == true) _endSession(reason: SessionEndReason.quit);
        },
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Lives (hearts)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Icon(
                i < provider.livesRemaining
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: i < provider.livesRemaining
                    ? const Color(0xFFE53935)
                    : AppTheme.textSecondary,
                size: 18,
              ),
            )),
          ),
          const SizedBox(width: 14),
          const Icon(Icons.local_fire_department_rounded,
              color: Color(0xFFFF6B35), size: 18),
          const SizedBox(width: 3),
          Text(
            '${provider.currentStreak}',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.star_rounded, color: AppTheme.primaryColor, size: 16),
          const SizedBox(width: 3),
          Text(
            '${provider.totalScore}',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
      centerTitle: true,
    );
  }

  Widget _buildError(GameSessionProvider provider) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(provider.trackError!,
              style: const TextStyle(color: AppTheme.textSecondary),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: provider.loadNextSong,
            child: Text(l10n.retry),
          ),
        ],
      ),
    );
  }

  Widget _buildGameBody(BuildContext context, GameSessionProvider provider) {
    if (context.isWide) return _buildWideGameBody(context, provider);
    return _buildNarrowGameBody(context, provider);
  }

  /// One centred stage, not a two-column split.
  ///
  /// The split put a 440px blurred square on the left and three small controls
  /// at the top of an otherwise empty right-hand column — the browser window
  /// made the emptiness worse, not better. Everything now sits on the centre
  /// line, in the order the round is played: listen, then guess.
  Widget _buildWideGameBody(
      BuildContext context, GameSessionProvider provider) {
    final track = provider.currentTrack;
    final revealed = provider.revealAnswer;

    return Stack(
      children: [
        CoverBackdrop(coverUrl: track?.coverUrl),
        // Keeps text legible over the wash, whatever the artwork's colours.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.backgroundColor.withValues(alpha: 0.72),
                    AppTheme.backgroundColor.withValues(alpha: 0.93),
                  ],
                ),
              ),
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            // The cover takes the height the rest of the stage does not need,
            // so a short browser window shrinks the artwork instead of pushing
            // the guess box off the bottom.
            final coverSize = constraints.maxHeight.isFinite
                ? (constraints.maxHeight - 430).clamp(120.0, 300.0)
                : 280.0;
            // Centred by [FullHeightScroll], which hands the column the
            // viewport's height without measuring the subtree — the result
            // list below the guess box cannot be measured.
            return FullHeightScroll(
              maxWidth: 620,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 28),
                  Center(child: SectionLabel(_stageLabel())),
                  const SizedBox(height: 18),
                  Center(child: _buildCover(provider, track, coverSize)),
                  const SizedBox(height: 28),
                  Center(child: _buildSnippetButton(provider)),
                  const SizedBox(height: 32),
                  if (revealed) ...[
                    _buildResultCard(provider, track),
                    const SizedBox(height: 20),
                    _buildAdvanceButton(provider, hint: true),
                  ] else ...[
                    _buildGuessField(provider, resultsBelow: true),
                    const SizedBox(height: 20),
                    Center(child: _buildGiveUpButton(provider)),
                  ],
                  const SizedBox(height: 28),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildNarrowGameBody(
    BuildContext context, GameSessionProvider provider) {
    final track = provider.currentTrack;
    final revealed = provider.revealAnswer;

    return Stack(
      children: [
        CoverBackdrop(coverUrl: track?.coverUrl),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.backgroundColor.withValues(alpha: 0.72),
                    AppTheme.backgroundColor.withValues(alpha: 0.93),
                  ],
                ),
              ),
            ),
          ),
        ),
        Column(
          children: [
            // Scrollable top section — shrinks when the keyboard opens.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final coverSize =
                        constraints.maxWidth.clamp(120.0, 260.0);
                    return Column(
                      children: [
                        SectionLabel(_stageLabel()),
                        const SizedBox(height: 16),
                        _buildCover(provider, track, coverSize),
                        const SizedBox(height: 24),
                        _buildSnippetButton(provider),
                        if (revealed) ...[
                          const SizedBox(height: 24),
                          _buildResultCard(provider, track),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
            // Fixed bottom section — always visible above the keyboard.
            if (!revealed) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _buildGuessField(provider, resultsBelow: false),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _buildGiveUpButton(provider),
              ),
            ],
            if (revealed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: _buildAdvanceButton(provider),
              ),
          ],
        ),
      ],
    );
  }

  /// What is being played — "RAP FR · HARD" — above the artwork. The run's
  /// own settings are the only context the screen has room for.
  String _stageLabel() {
    final source = widget.category?.name ?? widget.artistFilter;
    final difficulty = widget.difficulty.label;
    return source == null ? difficulty : '$source · $difficulty';
  }

  Widget _buildCover(
      GameSessionProvider provider, Track? track, double size) {
    return AnimatedBuilder(
      animation: _revealAnim,
      builder: (context, _) => CoverStage(
        coverUrl: track?.coverUrl,
        reveal: _revealAnim.value,
        size: size,
        loading: provider.isLoadingTrack,
      ),
    );
  }

  Widget _buildSnippetButton(GameSessionProvider provider) {
    final l10n = AppLocalizations.of(context);
    final revealed = provider.revealAnswer;
    // Once the answer is out the button plays the whole preview, so the rail
    // has to run over that length instead of the snippet's.
    final duration = revealed
        ? const Duration(seconds: 30)
        : provider.difficulty.snippetDuration;
    final label = provider.isLoadingTrack
        ? l10n.loading
        : provider.isPlaying
            ? l10n.gamePlaying
            : l10n.gamePlayWithDuration(revealed
                ? '30s'
                : _snippetLabel(provider.difficulty));

    return SnippetButton(
      label: label,
      snippetDuration: duration,
      playing: provider.isPlaying,
      loading: provider.isLoadingTrack,
      onTap: provider.isPlaying || provider.isLoadingTrack
          ? null
          // Clicking the button took the caret out of the guess box. Put it
          // back, so the player can type the answer without reaching for the
          // mouse again — and so Space still replays.
          : () {
              provider.replaySnippet();
              _focusGuessOnPointerLayout();
            },
    );
  }

  String _snippetLabel(Difficulty d) => switch (d) {
        Difficulty.easy => '15s',
        Difficulty.medium => '5s',
        Difficulty.hard => '1s',
      };

  Widget _buildGuessField(
    GameSessionProvider provider, {
    required bool resultsBelow,
  }) {
    final l10n = AppLocalizations.of(context);
    return GuessField(
      controller: _guessController,
      focusNode: _guessFocus,
      results: provider.searchResults,
      isSearching: provider.isSearching,
      hintText: l10n.gameSongInputHint,
      // The shortcut line is only useful where there is a physical keyboard,
      // which on this codebase is the same place the wide layout is used.
      keyboardHint: resultsBelow ? l10n.gameKeyboardHintGuess : null,
      resultsBelow: resultsBelow,
      onChanged: provider.searchTracks,
      onClear: provider.clearSearch,
      onSelected: (track) {
        // Focus moves to the shortcut host rather than nowhere, so Enter
        // advances to the next song straight after the answer is revealed.
        _shortcutFocus.requestFocus();
        _guessController.clear();
        provider.submitGuess(track);
      },
    );
  }

  Widget _buildGiveUpButton(GameSessionProvider provider) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: provider.giveUp,
        child: Text(l10n.gameGiveUp.toUpperCase()),
      ),
    );
  }

  Widget _buildResultCard(GameSessionProvider provider, Track? track) {
    final l10n = AppLocalizations.of(context);
    final isCorrect = provider.lastGuessResult == GuessResult.correct;
    final color = isCorrect ? const Color(0xFF4CAF50) : const Color(0xFFE53935);
    final icon = isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded;

    return AnimatedBuilder(
      animation: _revealAnim,
      builder: (context, _) {
        return Opacity(
          opacity: _revealAnim.value,
          child: Transform.translate(
            offset: Offset(0, (1 - _revealAnim.value) * 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: color, size: 22),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          (isCorrect ? l10n.gameCorrect : l10n.gameWrong)
                              .toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.action(color: color, size: 15),
                        ),
                      ),
                      if (isCorrect) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.2),
                            borderRadius:
                                BorderRadius.circular(AppTheme.borderRadius),
                          ),
                          child: Text(
                            '+${provider.totalScore > 0 ? (provider.songsCorrect > 0 ? 10 : 0) : 0} pts',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (track != null) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 12),
                    Text(
                      track.title,
                      style: AppTheme.title(19),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artist,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    if (track.releaseYear != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${track.releaseYear}',
                        style: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAdvanceButton(
    GameSessionProvider provider, {
    bool hint = false,
  }) {
    final l10n = AppLocalizations.of(context);
    final isGameOver = provider.endReason == SessionEndReason.outOfLives;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: provider.isLoadingTrack
                ? null
                : isGameOver
                    ? () => _endSession(reason: SessionEndReason.outOfLives)
                    : _nextSong,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isGameOver ? const Color(0xFFE53935) : AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.borderRadius)),
              elevation: 0,
            ),
            child: provider.isLoadingTrack
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          (isGameOver
                                  ? l10n.gameSeeResults
                                  : l10n.gameNextButton)
                              .toUpperCase(),
                          textAlign: TextAlign.center,
                          style: AppTheme.action(size: 15),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isGameOver
                            ? Icons.emoji_events_rounded
                            : Icons.arrow_forward_rounded,
                        size: 18,
                      ),
                    ],
                  ),
          ),
        ),
        if (hint) ...[
          const SizedBox(height: 10),
          Text(
            l10n.gameKeyboardHintNext,
            style: AppTheme.kicker(color: AppTheme.ink3, size: 9.5),
          ),
        ],
      ],
    );
  }
}
