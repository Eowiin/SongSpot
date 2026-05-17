import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/track.dart';
import '../../providers/duel_provider.dart';
import '../../services/api_service.dart';
import '../../services/audio_service.dart';

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

  bool _isPlaying = false;
  bool _isAudioLoading = false;
  List<Track> _searchResults = [];
  bool _isSearching = false;
  Timer? _searchDebounce;
  Timer? _revealTimer;
  bool _showRevealOverlay = false;
  String? _submittedTrackLabel;
  DuelProvider? _duel;

  // Track which round we've already loaded audio + reset UI for
  int _lastLoadedRound = 0;
  String? _loadedUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _duel = context.read<DuelProvider>();
      debugPrint('[DuelGame] initState postFrame: status=${_duel!.status} trackUrl=${_duel!.currentTrack?.previewUrl}');
      _lastLoadedRound = _duel!.currentRound;
      _duel!.addListener(_onDuelChanged);
      _loadAudio();
    });
  }

  @override
  void dispose() {
    _duel?.removeListener(_onDuelChanged);
    _searchDebounce?.cancel();
    _revealTimer?.cancel();
    _guessController.dispose();
    _guessFocus.dispose();
    _audio.dispose();
    super.dispose();
  }

  void _onDuelChanged() {
    debugPrint('[DuelGame] _onDuelChanged: mounted=$mounted status=${_duel?.status}');
    if (!mounted || _duel == null) return;

    // Only reset UI and reload audio when a genuinely new round starts.
    // Snippet extensions also fire notifyListeners() while status==playing,
    // so guard on round number to avoid clearing the input and re-fetching audio.
    if (_duel!.status == DuelStatus.playing &&
        _duel!.currentRound != _lastLoadedRound) {
      _lastLoadedRound = _duel!.currentRound;
      _resetForNewRound();
      _loadAudio();
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
      _isAudioLoading = false;
      _searchResults = [];
      _submittedTrackLabel = null;
      _showRevealOverlay = false;
      _guessController.clear();
      _loadedUrl = null;
    });
  }

  Future<void> _loadAudio() async {
    final track = _duel?.currentTrack;
    final url = track?.previewUrl;
    debugPrint('[DuelGame] _loadAudio: url=$url loadedUrl=$_loadedUrl');
    if (url == null || url.isEmpty || url == _loadedUrl) {
      debugPrint('[DuelGame] _loadAudio: skipped (null/empty/same)');
      return;
    }
    _loadedUrl = url;
    if (mounted) setState(() => _isAudioLoading = true);
    try {
      debugPrint('[DuelGame] _loadAudio: calling loadAudio($url)');
      await _audio.loadAudio(url);
      debugPrint('[DuelGame] _loadAudio: loadAudio succeeded');
    } catch (e) {
      debugPrint('[DuelGame] _loadAudio: loadAudio failed: $e — trying refresh');
      final trackId = track?.id;
      if (trackId != null && trackId.isNotEmpty) {
        try {
          final refreshed = await _api.refreshTrackPreview(trackId: trackId);
          final newUrl = refreshed['preview_url'] as String?;
          debugPrint('[DuelGame] _loadAudio: refreshed url=$newUrl');
          if (newUrl != null && newUrl.isNotEmpty && newUrl != url) {
            _loadedUrl = newUrl;
            await _audio.loadAudio(newUrl);
            debugPrint('[DuelGame] _loadAudio: retry succeeded');
          }
        } catch (e2) {
          debugPrint('[DuelGame] _loadAudio: refresh also failed: $e2');
        }
      }
    }
    if (mounted) setState(() => _isAudioLoading = false);
  }

  Future<void> _playSnippet() async {
    debugPrint('[DuelGame] _playSnippet: isPlaying=$_isPlaying isLoading=$_isAudioLoading duel=${_duel?.status}');
    if (_isPlaying) return;
    final duel = _duel;
    if (duel == null) return;
    final snippetIdx = (duel.snippetsUsed - 1).clamp(0, _snippetDurations.length - 1);
    setState(() => _isPlaying = true);
    try {
      await _audio.playSnippet(
        duration: _snippetDurations[snippetIdx],
        onPlaybackStopped: () {
          if (mounted) setState(() => _isPlaying = false);
        },
      );
    } catch (_) {
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  void _extendSnippet() {
    final duel = _duel;
    if (duel == null || duel.hasSubmitted || duel.snippetsUsed >= 5) return;
    _audio.stop();
    setState(() => _isPlaying = false);
    duel.requestNextSnippet();
  }

  void _searchTracks(String query) {
    _searchDebounce?.cancel();
    if (query.length < 2) {
      setState(() { _searchResults = []; _isSearching = false; });
      return;
    }
    setState(() => _isSearching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final results = await _api.searchTracks(query);
        if (!mounted) return;
        setState(() {
          _searchResults = results
              .map((j) => Track.fromJson(j as Map<String, dynamic>))
              .toList();
          _isSearching = false;
        });
      } catch (_) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  void _selectTrack(Track track) {
    _duel?.submitGuess(track.id);
    _guessFocus.unfocus();
    _guessController.clear();
    setState(() {
      _searchResults = [];
      _submittedTrackLabel = '${track.title} — ${track.artist}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DuelProvider>(
      builder: (context, duel, _) {
        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: _buildAppBar(duel),
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    _buildOpponentPanel(duel),
                    const SizedBox(height: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            _buildRoundIndicator(duel),
                            const SizedBox(height: 20),
                            _buildTrackCard(duel),
                            const SizedBox(height: 16),
                            _buildSnippetControls(duel),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                    // Fixed bottom section — always visible above keyboard.
                    // _showRevealOverlay (not duel.status) gates the overlay so the
                    // submitted banner always renders for ≥800ms before it appears.
                    if (!duel.hasSubmitted && !_showRevealOverlay) ...[
                      // Always at position 0 so the TextField never shifts position
                      // (Flutter reconciles Column children by index — inserting a
                      // widget above the TextField would recreate it and lose focus)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                        child: (_searchResults.isNotEmpty || _isSearching)
                            ? _buildSearchResults()
                            : const SizedBox.shrink(),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: _buildGuessField(),
                      ),
                    ] else if (duel.hasSubmitted && !_showRevealOverlay)
                      _buildSubmittedBanner(),
                  ],
                ),
                if (_showRevealOverlay) _buildRoundResultOverlay(context, duel),
              ],
            ),
          ),
        );
      },
    );
  }

  AppBar _buildAppBar(DuelProvider duel) {
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('vs', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
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

  Widget _buildOpponentPanel(DuelProvider duel) {
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
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_rounded, color: AppTheme.successColor, size: 14),
                  SizedBox(width: 4),
                  Text('Submitted', style: TextStyle(color: AppTheme.successColor, fontSize: 12)),
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

  Widget _buildTrackCard(DuelProvider duel) {
    final snippetIdx = (duel.snippetsUsed - 1).clamp(0, _snippetDurations.length - 1);
    final snippetDuration = _snippetDurations[snippetIdx];
    final seconds = snippetDuration.inSeconds;
    final durationLabel = seconds >= 60
        ? '${seconds ~/ 60}m'
        : '${seconds}s snippet';

    String statusLabel;
    if (_isAudioLoading) {
      statusLabel = 'Loading...';
    } else if (_isPlaying) {
      statusLabel = 'Playing $durationLabel...';
    } else {
      statusLabel = 'Tap to listen · $durationLabel';
    }

    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: (_isPlaying || _isAudioLoading) ? null : _playSnippet,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppTheme.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.4),
                    blurRadius: 16,
                  ),
                ],
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
          const SizedBox(height: 16),
          Text(
            statusLabel,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSnippetControls(DuelProvider duel) {
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
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${points[(current - 1).clamp(0, 4)]} pts',
                style: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        if (!duel.hasSubmitted && current < max) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _extendSnippet,
            icon: const Icon(Icons.expand_more_rounded, size: 16),
            label: Text('Extend to $nextDuration'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGuessField() {
    return TextField(
      controller: _guessController,
      focusNode: _guessFocus,
      style: const TextStyle(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        hintText: 'Search for a song...',
        hintStyle: const TextStyle(color: AppTheme.textSecondary),
        filled: true,
        fillColor: AppTheme.surfaceColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
        suffixIcon: _isSearching
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primaryColor,
                  ),
                ),
              )
            : null,
      ),
      onChanged: _searchTracks,
    );
  }

  Widget _buildSearchResults() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _searchResults.length,
        itemBuilder: (_, i) {
          final track = _searchResults[i];
          return ListTile(
            dense: true,
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: track.coverUrl != null
                  ? Image.network(
                      track.coverUrl!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => const _CoverPlaceholder(),
                    )
                  : const _CoverPlaceholder(),
            ),
            title: Text(
              track.title,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              track.artist,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _selectTrack(track),
          );
        },
      ),
    );
  }

  Widget _buildSubmittedBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.successColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
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
                const Text(
                  'Submitted — waiting for opponent...',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundResultOverlay(BuildContext context, DuelProvider duel) {
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
              borderRadius: BorderRadius.circular(24),
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
                  isCorrect ? '+${result.player.points} pts' : 'Wrong!',
                  style: TextStyle(
                    color: isCorrect ? AppTheme.successColor : AppTheme.errorColor,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
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
                      'You',
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
                const Text(
                  'Next round starting...',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      color: AppTheme.surfaceColor,
      child: const Icon(Icons.music_note_rounded, color: AppTheme.textSecondary, size: 20),
    );
  }
}
