import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../config/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/track.dart';
import '../../providers/duel_provider.dart';
import '../../services/api_service.dart';
import '../../services/audio_service.dart';
import '../../widgets/game_shortcuts.dart';
import '../../widgets/guess_field.dart';
import '../../widgets/pressable.dart';
import '../../widgets/snippet_stage.dart';

// Snippet durations matching the plan: 1s, 3s, 5s, 10s, 15s
const _snippetDurations = [
  Duration(seconds: 1),
  Duration(seconds: 3),
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 15),
];

class DuelGameScreen extends StatefulWidget {
  const DuelGameScreen({super.key});

  @override
  State<DuelGameScreen> createState() => _DuelGameScreenState();
}

class _DuelGameScreenState extends State<DuelGameScreen> {
  final _audio = AudioService();
  final _api = ApiService();
  final _guessController = TextEditingController();
  final _guessFocus = FocusNode();
  /// Holds keyboard focus whenever the guess box does not, so Space reaches
  /// the replay shortcut.
  final _shortcutFocus = FocusNode(debugLabel: 'duel shortcuts');

  bool _isPlaying = false;
  /// The snippet is actually sounding, as opposed to [_isPlaying], which is
  /// already true while the player buffers. The progress rail runs off this.
  bool _isSounding = false;
  bool _isAudioLoading = false;
  List<Track> _searchResults = [];
  bool _isSearching = false;
  Timer? _searchDebounce;
  int _searchRequestId = 0;
  Timer? _revealTimer;
  bool _showRevealOverlay = false;
  String? _submittedTrackLabel;
  DuelProvider? _duel;

  // Mirrors DuelProvider.roundVersion — audio is reloaded whenever these differ.
  int _lastLoadedVersion = 0;
  String? _loadedUrl;

  @override
  void initState() {
    super.initState();
    // Mirror the player's real state: a snippet also ends on a submit, a new
    // round or an interruption, and none of those fire onPlaybackStopped.
    _audio.playing.addListener(_onAudioPlayingChanged);
    _audio.sounding.addListener(_onAudioSoundingChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _duel = context.read<DuelProvider>();
      _lastLoadedVersion = _duel!.roundVersion;
      _duel!.addListener(_onDuelChanged);
      _loadAndSignalReady();
    });
  }

  void _onAudioPlayingChanged() {
    final playing = _audio.playing.value;
    if (!mounted || _isPlaying == playing) return;
    setState(() => _isPlaying = playing);
  }

  void _onAudioSoundingChanged() {
    final sounding = _audio.sounding.value;
    if (!mounted || _isSounding == sounding) return;
    setState(() => _isSounding = sounding);
  }

  @override
  void dispose() {
    _audio.playing.removeListener(_onAudioPlayingChanged);
    _audio.sounding.removeListener(_onAudioSoundingChanged);
    _duel?.removeListener(_onDuelChanged);
    _searchDebounce?.cancel();
    _revealTimer?.cancel();
    _guessController.dispose();
    _guessFocus.dispose();
    _shortcutFocus.dispose();
    _audio.stop(); // AudioService is a singleton — never call dispose() on it
    super.dispose();
  }

  void _onDuelChanged() {
    if (!mounted || _duel == null) return;

    // Trigger audio load when the server sends round_start (status → loading).
    // Guard on round number so snippet extensions don't re-fetch audio.
    if (_duel!.status == DuelStatus.loading &&
        _duel!.roundVersion != _lastLoadedVersion) {
      _lastLoadedVersion = _duel!.roundVersion;
      _resetForNewRound();
      _loadAndSignalReady();
    }

    // Guard the reveal overlay behind a short timer so the submitted banner
    // always has time to render — even when round_result arrives in the same
    // event-loop batch as the submit (common on Android with low-latency servers).
    if (_duel!.status == DuelStatus.roundReveal && !_showRevealOverlay) {
      _revealTimer ??= Timer(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _showRevealOverlay = true);
        _revealTimer = null;
      });
    } else if (_duel!.status != DuelStatus.roundReveal) {
      _revealTimer?.cancel();
      _revealTimer = null;
    }
  }

  void _resetForNewRound() {
    _revealTimer?.cancel();
    _revealTimer = null;
    setState(() {
      _isPlaying = false;
      _isSounding = false;
      _isAudioLoading = false;
      _searchResults = [];
      _searchRequestId++;
      _submittedTrackLabel = null;
      _showRevealOverlay = false;
      _guessController.clear();
      _loadedUrl = null;
    });
  }

  Future<void> _loadAndSignalReady() async {
    if (_duel?.currentTrack == null) return; // round_start not yet received; _onDuelChanged will retry
    await _loadAudio();
    _duel?.notifyAudioReady();
  }

  Future<void> _loadAudio() async {
    final track = _duel?.currentTrack;
    final url = track?.previewUrl;
    if (url == null || url.isEmpty || url == _loadedUrl) return;
    _loadedUrl = url;
    if (mounted) setState(() => _isAudioLoading = true);
    try {
      await _audio.loadAudio(url);
    } catch (e) {
      final trackId = track?.id;
      if (trackId != null && trackId.isNotEmpty) {
        try {
          final refreshed = await _api.refreshTrackPreview(trackId: trackId);
          final newUrl = refreshed['preview_url'] as String?;
          if (newUrl != null && newUrl.isNotEmpty && newUrl != url) {
            _loadedUrl = newUrl;
            await _audio.loadAudio(newUrl);
          }
        } catch (_) {}
      }
    }
    if (mounted) setState(() => _isAudioLoading = false);
  }

  Future<void> _playSnippet() async {
    if (_isPlaying) return;
    final duel = _duel;
    if (duel == null) return;
    final snippetIdx = (duel.snippetsUsed - 1).clamp(0, _snippetDurations.length - 1);
    setState(() => _isPlaying = true);
    try {
      await _audio.playSnippet(
        duration: _snippetDurations[snippetIdx],
        onPlaybackStopped: () {
          if (mounted) {
            setState(() {
              _isPlaying = false;
              _isSounding = false;
            });
          }
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _isSounding = false;
        });
      }
    }
  }

  void _extendSnippet() {
    final duel = _duel;
    if (duel == null || duel.hasSubmitted || duel.snippetsUsed >= 5) return;
    _audio.stop();
    setState(() {
      _isPlaying = false;
      _isSounding = false;
    });
    duel.requestNextSnippet();
  }

  void _searchTracks(String query) {
    _searchDebounce?.cancel();
    // Cancelling the timer only stops a request not yet sent. One already on
    // the wire cannot be called back, and Deezer answers out of order often
    // enough that the reply to `ro` lands after the reply to `rosalia` and
    // overwrites it — so every reply carries the id it was sent under, and one
    // that is no longer the newest is dropped.
    final requestId = ++_searchRequestId;
    if (query.length < 2) {
      setState(() { _searchResults = []; _isSearching = false; });
      return;
    }
    setState(() => _isSearching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      List<Track> results;
      try {
        final json = await _api.searchTracks(query);
        results = json
            .map((j) => Track.fromJson(j as Map<String, dynamic>))
            .toList();
      } catch (_) {
        results = [];
      }
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    });
  }

  void _selectTrack(Track track) {
    _duel?.submitGuess(track.id);
    _shortcutFocus.requestFocus();
    _guessController.clear();
    setState(() {
      _searchResults = [];
      _searchRequestId++;
      _submittedTrackLabel = '${track.title} — ${track.artist}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Consumer<DuelProvider>(
      builder: (context, duel, _) {
        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: _buildAppBar(duel, l10n),
          body: SafeArea(
            child: _withDuelShortcuts(
              duel,
              Stack(
                children: [
                  context.isWide
                      ? _buildWideDuelBody(duel, l10n)
                      : _buildNarrowDuelBody(duel, l10n),
                  if (duel.status == DuelStatus.loading)
                    _buildReadyOverlay(duel, l10n),
                  if (_showRevealOverlay)
                    _buildRoundResultOverlay(context, duel),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// See [GameShortcuts] for why Space is live inside an empty guess box.
  /// The duel has no Enter action: rounds advance on the server's clock.
  Widget _withDuelShortcuts(DuelProvider duel, Widget child) {
    return GameShortcuts(
      hostFocus: _shortcutFocus,
      guessFocus: _guessFocus,
      guessController: _guessController,
      canReplay: () =>
          !_isPlaying &&
          !_isAudioLoading &&
          duel.status == DuelStatus.playing,
      onReplay: _playSnippet,
      child: child,
    );
  }

  /// Desktop-style split: the track and its controls on the left, the guess
  /// box and opponent state on the right. Phones keep the stacked layout so
  /// the guess field stays pinned above the soft keyboard.
  Widget _buildWideDuelBody(DuelProvider duel, AppLocalizations l10n) {
    return ResponsiveCenter(
      maxWidth: 1100,
      child: Column(
        children: [
          _buildOpponentPanel(duel, l10n),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 6,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        if (duel.errorMessage != null)
                          _buildConnectionBanner(duel.errorMessage!),
                        _buildRoundIndicator(duel),
                        const SizedBox(height: 24),
                        _buildTrackCard(duel, l10n),
                        const SizedBox(height: 20),
                        _buildSnippetControls(duel, l10n),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 36),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!duel.hasSubmitted && !_showRevealOverlay)
                        _buildGuessField(l10n, resultsBelow: true)
                      else if (duel.hasSubmitted && !_showRevealOverlay)
                        _buildSubmittedBanner(l10n),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildNarrowDuelBody(DuelProvider duel, AppLocalizations l10n) {
    return Column(
      children: [
        _buildOpponentPanel(duel, l10n),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 8),
                if (duel.errorMessage != null)
                  _buildConnectionBanner(duel.errorMessage!),
                _buildRoundIndicator(duel),
                const SizedBox(height: 20),
                _buildTrackCard(duel, l10n),
                const SizedBox(height: 16),
                _buildSnippetControls(duel, l10n),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        if (!duel.hasSubmitted && !_showRevealOverlay)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: _buildGuessField(l10n, resultsBelow: false),
          )
        else if (duel.hasSubmitted && !_showRevealOverlay)
          _buildSubmittedBanner(l10n),
      ],
    );
  }

  AppBar _buildAppBar(DuelProvider duel, AppLocalizations l10n) {
    final timeRemaining = duel.roundTimeRemaining;
    final showTimer = duel.status == DuelStatus.playing && timeRemaining > 0;
    final timerColor = timeRemaining <= 10
        ? AppTheme.errorColor
        : timeRemaining <= 20
            ? Colors.orange
            : AppTheme.textSecondary;

    return AppBar(
      backgroundColor: AppTheme.backgroundColor,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${duel.playerScore}',
            style: const TextStyle(
              color: AppTheme.primaryColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: showTimer
                ? Text(
                    '${timeRemaining}s',
                    style: TextStyle(
                      color: timerColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  )
                : Text(l10n.duelVs, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          ),
          Text(
            '${duel.opponentScore}',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      centerTitle: true,
    );
  }

  Widget _buildOpponentPanel(DuelProvider duel, AppLocalizations l10n) {
    final opponent = duel.opponent;
    return Container(
      color: AppTheme.surfaceColor,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.2),
            child: Text(
              (opponent?.username ?? '?')[0].toUpperCase(),
              style: const TextStyle(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  opponent?.username ?? '...',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  'ELO ${opponent?.elo ?? '—'}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          if (duel.opponentSubmitted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                border: Border.all(
                    color: AppTheme.successColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_rounded, color: AppTheme.successColor, size: 14),
                  const SizedBox(width: 4),
                  Text(l10n.duelOpponentSubmitted, style: const TextStyle(color: AppTheme.successColor, fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRoundIndicator(DuelProvider duel) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(duel.totalRounds, (i) {
        final done = i < duel.currentRound - 1;
        final current = i == duel.currentRound - 1;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: current ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: done
                ? AppTheme.primaryColor
                : current
                    ? AppTheme.primaryColor.withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.15),
          ),
        );
      }),
    );
  }

  Widget _buildTrackCard(DuelProvider duel, AppLocalizations l10n) {
    final snippetIdx = (duel.snippetsUsed - 1).clamp(0, _snippetDurations.length - 1);
    final snippetDuration = _snippetDurations[snippetIdx];
    final seconds = snippetDuration.inSeconds;
    final durationLabel = l10n.duelSnippetLabel(seconds);

    final String statusLabel;
    if (_isAudioLoading) {
      statusLabel = l10n.duelLoadingAudio;
    } else if (_isPlaying) {
      statusLabel = l10n.duelPlayingSnippet(durationLabel);
    } else {
      statusLabel = l10n.duelTapToListen(durationLabel);
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 180),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Pressable(
            onTap: (_isPlaying || _isAudioLoading) ? null : _playSnippet,
            borderRadius: AppTheme.borderRadius,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                gradient: AppTheme.primaryGradient,
              ),
              child: _isAudioLoading
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Icon(
                      _isPlaying ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
            ),
          ),
          const SizedBox(height: 14),
          SnippetProgressRail(
            duration: snippetDuration,
            sounding: _isSounding,
            width: 200,
          ),
          const SizedBox(height: 14),
          Text(
            statusLabel,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSnippetControls(DuelProvider duel, AppLocalizations l10n) {
    const max = 5;
    final current = duel.snippetsUsed;
    final points = [100, 80, 60, 40, 20];
    final durations = ['1s', '3s', '5s', '10s', '15s'];
    final nextDuration = current < max ? durations[current] : null;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Snippet dots
            ...List.generate(max, (i) {
              final used = i < current;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: used
                      ? AppTheme.primaryColor
                      : Colors.white.withValues(alpha: 0.2),
                ),
              );
            }),
            const SizedBox(width: 16),
            // Points badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppTheme.borderRadius),
              ),
              child: Text(
                '${points[(current - 1).clamp(0, 4)]} ${l10n.duelPts}',
                style: AppTheme.action(
                    color: AppTheme.primaryColor, size: 12),
              ),
            ),
          ],
        ),
        if (!duel.hasSubmitted && current < max) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _extendSnippet,
            icon: const Icon(Icons.expand_more_rounded, size: 16),
            label: Text(l10n.duelExtendTo(nextDuration!)),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGuessField(
    AppLocalizations l10n, {
    required bool resultsBelow,
  }) {
    return GuessField(
      controller: _guessController,
      focusNode: _guessFocus,
      results: _searchResults,
      isSearching: _isSearching,
      hintText: l10n.duelSearchHint,
      keyboardHint: resultsBelow ? l10n.gameKeyboardHintGuess : null,
      resultsBelow: resultsBelow,
      // Focusing the box on arrival would swallow the Space shortcut, and the
      // duel opens on a "get ready" overlay anyway.
      autofocus: false,
      maxResultsHeight: 220,
      onChanged: _searchTracks,
      onClear: () => setState(() {
        _searchResults = [];
        _searchRequestId++;
      }),
      onSelected: _selectTrack,
    );
  }

  Widget _buildSubmittedBanner(AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.successColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
        border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppTheme.successColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_submittedTrackLabel != null)
                  Text(
                    _submittedTrackLabel!,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 2),
                Text(
                  l10n.duelYouSubmittedWaiting,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.orange.withValues(alpha: 0.15),
      child: Text(
        message,
        style: const TextStyle(color: Colors.orange, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildReadyOverlay(DuelProvider duel, AppLocalizations l10n) {
    final label = duel.localAudioReady
        ? l10n.duelWaitingOpponent
        : l10n.duelLoadingAudio;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.primaryColor),
              const SizedBox(height: 16),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoundResultOverlay(BuildContext context, DuelProvider duel) {
    final l10n = AppLocalizations.of(context);
    final result = duel.lastRoundResult;
    if (result == null) return const SizedBox.shrink();

    final isCorrect = result.player.correct;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
              border: Border.all(
                color: isCorrect
                    ? AppTheme.successColor.withValues(alpha: 0.4)
                    : AppTheme.errorColor.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: isCorrect ? AppTheme.successColor : AppTheme.errorColor,
                  size: 52,
                ),
                const SizedBox(height: 12),
                Text(
                  isCorrect
                      ? '+${result.player.points} ${l10n.duelPts}'
                      : l10n.duelWrong,
                  textAlign: TextAlign.center,
                  style: AppTheme.display(
                    28,
                    color:
                        isCorrect ? AppTheme.successColor : AppTheme.errorColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${result.track.title ?? ''}\n${result.track.artist ?? ''}',
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildResultCell(
                      l10n.duelYou,
                      '${result.playerScore}',
                      AppTheme.primaryColor,
                    ),
                    _buildResultCell(
                      duel.opponent?.username ?? 'Opponent',
                      '${result.opponentScore}',
                      AppTheme.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.duelNextRound,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultCell(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      ],
    );
  }
}

