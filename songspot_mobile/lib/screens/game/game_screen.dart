import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/app_theme.dart';
import '../../config/admob_config.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/room_provider.dart';
import '../../providers/pack_bundle_provider.dart';
import '../../providers/pack_provider.dart';
import '../../models/track.dart';
import '../../models/game_session.dart';
import '../../models/pack.dart';
import '../../models/message.dart';
import '../../models/user.dart';
import '../../widgets/compact_playback_panel.dart';
import '../../widgets/result_chat_section.dart';
import '../../widgets/result_leaderboard_section.dart';
import '../../widgets/result_track_card.dart';
import '../../widgets/track_autocomplete.dart';
import '../../widgets/gradient_button.dart';
import '../../services/api_service.dart';
import '../../services/admob_service.dart';
import '../../services/audio_service.dart';
import '../../models/history_day.dart';
import '../packs/pack_list_screen.dart';
import '../packs/pack_bundle_screen.dart';
import '../room/room_detail_screen.dart';

class GameScreen extends StatefulWidget {
  final String roomId;

  const GameScreen({super.key, required this.roomId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  static const List<double> _snippetTimelineWeights = [1, 1, 2, 3, 4, 5];
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _contentScrollController = ScrollController();
  final _dateScrollController = ScrollController();
  final AudioService _previewAudioService = AudioService();
  Track? _selectedTrack;
  String? _activePackId;
  String? _activePackName;
  late GameProvider _gameProvider;
  bool _pendingChatAutoScroll = false;
  int _lastKnownMessageCount = 0;
  bool _isPreviewPlaying = false;
  int _previewPlaybackRequestId = 0;
  String? _previewTrackId;

  // History
  final _apiService = ApiService();
  String? _selectedHistoryDate; // null = active game (today)
  Map<String, HistoryDay> _historyMap = {};
  HistoryDayDetail? _historyDetail;
  bool _historyDetailLoading = false;

  // Pack bundle history (populated when _activePackId != null)
  Map<String, PackHistoryDay> _packHistoryMap = {};
  PackHistoryDayDetail? _packHistoryDetail;
  bool _completionRecorded = false;
  bool _completionAdInProgress = false;
  int _completionAdAttempts = 0;
  bool _retryActivationInProgress = false;
  bool _showHistorySelector = false;
  Timer? _resultRefreshTimer;
  Timer? _skipFeedbackTimer;
  bool _skipFeedbackActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gameProvider = context.read<GameProvider>();
    _lastKnownMessageCount = _gameProvider.messages.length;
    _gameProvider.addListener(_handleGameProviderUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _gameProvider.startGameSession(widget.roomId);
      await _gameProvider.loadLeaderboard(widget.roomId);
      _gameProvider.connectToChat(widget.roomId);
      if (_gameProvider.currentSession?.isCompleted ?? false) {
        _startResultRefreshTimer();
      }
      // Load room details for name and host info
      context.read<RoomProvider>().loadRoomDetails(widget.roomId);
      context.read<PackProvider>().loadMyPacks(widget.roomId);
      _loadHistoryList();
      final adsDisabled = context.read<AuthProvider>().user?.hasNoAds ?? false;
      unawaited(AdMobService().preloadInterstitial(adsDisabled: adsDisabled));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resultRefreshTimer?.cancel();
    _skipFeedbackTimer?.cancel();
    _gameProvider.removeListener(_handleGameProviderUpdate);
    _gameProvider.disconnectFromChat();
    _titleController.dispose();
    _messageController.dispose();
    _contentScrollController.dispose();
    _dateScrollController.dispose();
    _previewAudioService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_gameProvider.audioService.stop());
        _previewPlaybackRequestId += 1;
        unawaited(_previewAudioService.stop());
        if (_isPreviewPlaying) {
          setState(() {
            _isPreviewPlaying = false;
            _previewTrackId = null;
          });
        }
        break;
    }
  }

  void _handleGameProviderUpdate() {
    if (!mounted) return;
    final count = _gameProvider.messages.length;
    final newMessagesArrived = count > _lastKnownMessageCount;
    _lastKnownMessageCount = count;
    if (_pendingChatAutoScroll && newMessagesArrived) {
      _scrollToLatestChatMessage();
    }
  }

  void _requestChatAutoScroll() {
    _pendingChatAutoScroll = true;
    _scrollToLatestChatMessage();
  }

  void _scrollToLatestChatMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_contentScrollController.hasClients) return;
      final max = _contentScrollController.position.maxScrollExtent;
      _contentScrollController.animateTo(
        max,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
      _pendingChatAutoScroll = false;
    });
  }

  Future<void> _handlePlaySnippet() async {
    final gameProvider = context.read<GameProvider>();
    try {
      await gameProvider.playCurrentSnippet();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to play audio: $e'),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _toggleResultPreview(Track track) async {
    if (_isPreviewPlaying && _previewTrackId == track.id) {
      _previewPlaybackRequestId += 1;
      await _previewAudioService.stop();
      if (mounted) {
        setState(() {
          _isPreviewPlaying = false;
          _previewTrackId = null;
        });
      }
      return;
    }

    final previewUrl = track.previewUrl.trim();
    if (previewUrl.isEmpty) return;

    final requestId = ++_previewPlaybackRequestId;
    if (mounted) {
      setState(() {
        _isPreviewPlaying = true;
        _previewTrackId = track.id;
      });
    }

    try {
      await _playResultPreviewWithRefresh(track, previewUrl);
    } catch (e) {
      if (!mounted || requestId != _previewPlaybackRequestId) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } finally {
      if (mounted && requestId == _previewPlaybackRequestId) {
        setState(() {
          _isPreviewPlaying = false;
          _previewTrackId = null;
        });
      }
    }
  }

  Future<void> _playResultPreviewWithRefresh(
    Track track,
    String previewUrl,
  ) async {
    if (previewUrl.isNotEmpty) {
      try {
        await _previewAudioService.loadAudio(previewUrl);
        await _previewAudioService.playFullAudio();
        return;
      } catch (_) {
        // Fall through to refresh and retry.
      }
    }

    final refreshed = await _apiService.refreshTrackPreview(trackId: track.id);
    final trackJson = refreshed['track'] as Map<String, dynamic>;
    final refreshedTrack = Track.fromJson(trackJson);
    await _previewAudioService.loadAudio(refreshedTrack.previewUrl);
    await _previewAudioService.playFullAudio();
  }

  Future<void> _handleSkip() async {
    final gameProvider = context.read<GameProvider>();
    final previousSession = gameProvider.currentSession;
    if (previousSession == null) return;
    final previousSnippet = previousSession.currentSnippet;
    unawaited(HapticFeedback.mediumImpact());
    unawaited(SystemSound.play(SystemSoundType.click));
    await gameProvider.skipSnippet(widget.roomId);
    if (!mounted) return;

    final updatedSession = gameProvider.currentSession;
    if (updatedSession == null) return;

    if (updatedSession.currentSnippet > previousSnippet) {
      _triggerSkipFeedbackAnimation();
      return;
    }

    final errorMessage = gameProvider.errorMessage;
    if (errorMessage != null && errorMessage.isNotEmpty) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage.replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  void _triggerSkipFeedbackAnimation() {
    _skipFeedbackTimer?.cancel();
    setState(() => _skipFeedbackActive = true);
    _skipFeedbackTimer = Timer(const Duration(milliseconds: 240), () {
      if (!mounted) return;
      setState(() => _skipFeedbackActive = false);
    });
  }

  String _formatSnippetDuration(double seconds) {
    final hasDecimal = seconds % 1 != 0;
    final value = hasDecimal
        ? seconds.toStringAsFixed(1)
        : seconds.toStringAsFixed(0);
    return '${value}s';
  }

  Future<void> _handleGuess() async {
    if (_selectedTrack == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a song from the search results'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    final gameProvider = context.read<GameProvider>();
    final previousGuesses = gameProvider.currentSession?.guessesMade ?? 0;

    final guessResponse = await gameProvider.submitGuess(
      roomId: widget.roomId,
      trackId: _selectedTrack!.id,
    );

    if (mounted) {
      if (guessResponse == null) {
        return;
      }
      final isCorrect = guessResponse['is_correct'] as bool? ?? false;
      final updatedCoins = guessResponse['coins'] as int?;
      final coinsAwarded = guessResponse['coins_awarded'] as int? ?? 0;
      final streakBonus = guessResponse['streak_bonus'] as int? ?? 0;
      final authProvider = context.read<AuthProvider>();
      if (updatedCoins != null) {
        authProvider.updateCoinsBalance(updatedCoins);
        unawaited(authProvider.refreshProfile());
      } else if (coinsAwarded > 0 || streakBonus > 0) {
        final currentCoins = authProvider.user?.coins ?? 0;
        authProvider.updateCoinsBalance(
          currentCoins + coinsAwarded + streakBonus,
        );
        unawaited(authProvider.refreshProfile());
      }

      final updatedSession = gameProvider.currentSession;
      final guessWasCounted =
          (updatedSession?.guessesMade ?? previousGuesses) > previousGuesses;
      if (guessWasCounted) {
        _titleController.clear();
        _selectedTrack = null;
      }
      if (updatedSession != null && (isCorrect || updatedSession.isCompleted)) {
        await _onGameCompleted();
      }
      if (!mounted) return;
      if (updatedSession != null &&
          !updatedSession.isCompleted &&
          updatedSession.awaitingRetryUnlock &&
          updatedSession.nextRetryRequirement == 'ad') {
        final adsDisabled =
            context.read<AuthProvider>().user?.hasNoAds ?? false;
        unawaited(
          AdMobService().preloadRewarded(
            adsDisabled: adsDisabled,
            placement: RewardedPlacement.retryUnlock,
          ),
        );
      }
    }
  }

  Future<void> _onGameCompleted() async {
    if (_completionRecorded || _completionAdInProgress) return;

    final gameProvider = context.read<GameProvider>();
    if (_completionAdAttempts == 0) {
      // Refresh leaderboard and load messages once when game is completed
      gameProvider.loadLeaderboard(widget.roomId);
      gameProvider.loadMessages(widget.roomId);
      _startResultRefreshTimer();
    }

    _completionAdAttempts += 1;
    if (mounted) {
      setState(() => _completionAdInProgress = true);
    }

    final session = gameProvider.currentSession;
    if (session == null) {
      if (mounted) {
        setState(() => _completionAdInProgress = false);
      }
      return;
    }

    final adsDisabled = context.read<AuthProvider>().user?.hasNoAds ?? false;
    final shown = await AdMobService().tryShowInterstitialForRoomCompletion(
      adsDisabled: adsDisabled,
      completionScope: 'daily',
      roomId: widget.roomId,
      gameDate: session.dailySong.date,
    );
    if (!shown && !adsDisabled) {
      await AdMobService().preloadInterstitial(adsDisabled: false);
    }
    if (shown || adsDisabled || _completionAdAttempts >= 2) {
      _completionRecorded = true;
    }
    unawaited(
      AdMobService().preloadRewarded(
        adsDisabled: adsDisabled,
        placement: RewardedPlacement.retryUnlock,
      ),
    );
    if (mounted) {
      setState(() => _completionAdInProgress = false);
    }
  }

  void _startResultRefreshTimer() {
    if (_resultRefreshTimer != null) return;

    _resultRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      if (!(_gameProvider.currentSession?.isCompleted ?? false)) return;
      _gameProvider.loadLeaderboard(widget.roomId, silent: true);
    });
  }

  Future<bool> _onWillPop() async {
    return true;
  }

  void _toggleHistorySelector() {
    setState(() {
      _showHistorySelector = !_showHistorySelector;
      if (!_showHistorySelector) {
        _selectedHistoryDate = null;
      }
    });
  }

  Future<void> _openRoomDetails() async {
    final room = context.read<RoomProvider>().currentRoom;
    if (room == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomDetailScreen(room: room, showPlayButton: false),
      ),
    );

    if (!mounted) return;
    await context.read<RoomProvider>().loadRoomDetails(widget.roomId);
  }

  Future<void> _openPackList() async {
    final room = context.read<RoomProvider>().currentRoom;
    if (room == null) return;

    await context.read<GameProvider>().stopPlayback();
    if (!mounted) return;

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PackListScreen(roomId: room.id)));
  }

  Future<void> _handleActivateRetry(String action) async {
    if (_retryActivationInProgress) return;

    setState(() => _retryActivationInProgress = true);
    final gameProvider = context.read<GameProvider>();

    try {
      Map<String, dynamic>? response;
      if (action == 'ad') {
        final adsDisabled =
            context.read<AuthProvider>().user?.hasNoAds ?? false;
        if (adsDisabled) {
          response = await gameProvider.activateRetry(
            roomId: widget.roomId,
            action: 'ad',
          );
        } else {
          final result = await AdMobService().showRewarded(
            adsDisabled: false,
            placement: RewardedPlacement.retryUnlock,
            onRewardEarned: () async {
              response = await gameProvider.activateRetry(
                roomId: widget.roomId,
                action: 'ad',
              );
            },
          );
          if (result == RewardedAdShowResult.unavailable) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ad not ready yet. Please retry in a moment.'),
                  backgroundColor: AppTheme.errorColor,
                ),
              );
            }
            return;
          }
        }
      } else {
        response = await gameProvider.activateRetry(
          roomId: widget.roomId,
          action: action,
        );
      }

      if (!mounted) return;
      final resolvedResponse = response;
      if (resolvedResponse == null) {
        final error =
            gameProvider.errorMessage ??
            'Unable to unlock retry. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.replaceFirst('Exception: ', '')),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        return;
      }
      final updatedCoins = resolvedResponse['coins'] as int?;
      if (updatedCoins != null) {
        context.read<AuthProvider>().updateCoinsBalance(updatedCoins);
      }
      if (gameProvider.currentSession?.isCompleted ?? false) {
        await _onGameCompleted();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _retryActivationInProgress = false);
      }
    }
  }

  DateTime _activeGameDate() {
    final now = DateTime.now().toUtc();
    final base = DateTime.utc(now.year, now.month, now.day);
    return now.hour < 12 ? base.subtract(const Duration(days: 1)) : base;
  }

  Future<void> _loadHistoryList() async {
    try {
      final data = await _apiService.getRoomHistory(widget.roomId, limit: 31);
      if (!mounted) return;
      final days = (data['results'] as List)
          .map((j) => HistoryDay.fromJson(j as Map<String, dynamic>))
          .toList();
      setState(() {
        _historyMap = {for (final d in days) d.date: d};
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_dateScrollController.hasClients) {
          _dateScrollController.animateTo(
            _dateScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (_) {
      // History chips are optional; fail silently
    }
  }

  Future<void> _selectDate(String? dateStr) async {
    if (dateStr == _selectedHistoryDate) return;
    if (dateStr == null) {
      setState(() => _selectedHistoryDate = null);
      return;
    }

    // If a pack is active, load pack bundle history instead
    if (_activePackId != null) {
      setState(() {
        _selectedHistoryDate = dateStr;
        _packHistoryDetail = null;
        _historyDetailLoading = true;
      });
      try {
        final data = await _apiService.getPackBundleHistoryDetail(
          widget.roomId,
          _activePackId!,
          dateStr,
        );
        if (mounted) {
          setState(() {
            _packHistoryDetail = PackHistoryDayDetail.fromJson(data);
            _historyDetailLoading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _historyDetailLoading = false);
      }
      return;
    }

    setState(() {
      _selectedHistoryDate = dateStr;
      _historyDetail = null;
      _historyDetailLoading = true;
    });
    try {
      final data = await _apiService.getRoomHistoryDetail(
        widget.roomId,
        dateStr,
      );
      if (mounted) {
        setState(() {
          _historyDetail = HistoryDayDetail.fromJson(data);
          _historyDetailLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _historyDetailLoading = false);
    }
  }

  Future<void> _loadPackHistoryList(String packId) async {
    try {
      final data = await _apiService.getPackBundleHistory(
        widget.roomId,
        packId,
        limit: 31,
      );
      if (!mounted) return;
      final days = (data['results'] as List)
          .map((j) => PackHistoryDay.fromJson(j as Map<String, dynamic>))
          .toList();
      setState(() {
        _packHistoryMap = {for (final d in days) d.date: d};
      });
    } catch (_) {
      // Fail silently
    }
  }

  Widget _buildPackSwitcher(BuildContext context, List<SongPack> packs) {
    final activePacks = packs.where((pack) => pack.trackCount > 0).toList();
    if (activePacks.isEmpty) {
      return const SizedBox.shrink();
    }

    final isDailySelected = _activePackId == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Switch challenge',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Daily'),
                selected: isDailySelected,
                onSelected: (_) async {
                  await context.read<GameProvider>().stopPlayback();
                  if (!mounted) return;
                  setState(() {
                    _activePackId = null;
                    _activePackName = null;
                    _selectedHistoryDate = null;
                    _packHistoryMap = {};
                    _packHistoryDetail = null;
                  });
                },
                selectedColor: AppTheme.primaryColor.withValues(alpha: 0.2),
              ),
              const SizedBox(width: 8),
              ...activePacks.map((pack) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(pack.name),
                    selected: pack.id == _activePackId,
                    onSelected: (_) async {
                      await context.read<GameProvider>().stopPlayback();
                      if (!mounted) return;
                      setState(() {
                        _activePackId = pack.id;
                        _activePackName = pack.name;
                        _selectedHistoryDate = null;
                        _packHistoryDetail = null;
                      });
                      _loadPackHistoryList(pack.id);
                    },
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _handleSendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    final gameProvider = context.read<GameProvider>();
    final success = await gameProvider.sendMessage(widget.roomId, message);

    if (success && mounted) {
      _messageController.clear();
      _requestChatAutoScroll();
    }
  }

  Future<void> _handlePackSendMessage() async {
    final message = _messageController.text.trim();
    final packId = _activePackId;
    if (message.isEmpty || packId == null) return;

    final provider = context.read<PackBundleProvider>();
    final success = await provider.sendMessage(
      roomId: widget.roomId,
      packId: packId,
      message: message,
    );

    if (success && mounted) {
      _messageController.clear();
      _requestChatAutoScroll();
    }
  }

  Widget _buildLoadingSkeleton() {
    return SingleChildScrollView(
      padding: AppTheme.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Progress Indicators Skeleton
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (index) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.surfaceColor,
                  border: Border.all(
                    color: AppTheme.textSecondary.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 32),

          // Audio Player Card Skeleton
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: AppTheme.cardGradient,
              borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
            ),
            child: Column(
              children: [
                // Icon placeholder
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Title skeleton
                Container(
                  width: 120,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 8),
                // Subtitle skeleton
                Container(
                  width: 60,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                // Points skeleton
                Container(
                  width: 80,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 24),
                // Button skeleton
                Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Guess Form Skeleton
          Container(
            width: 150,
            height: 24,
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(AppTheme.borderRadius),
            ),
          ),
          const SizedBox(height: 24),

          // Action Buttons Skeleton
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultContent(
    GameSession session,
    List<LeaderboardEntry> leaderboard,
  ) {
    final l10n = AppLocalizations.of(context);
    final track = session.dailySong.track;
    final isCorrect = session.correctGuess;
    final leaderboardRows = leaderboard
        .map(
          (entry) => ResultLeaderboardRowData(
            title: entry.user.username,
            subtitle: entry.pointsEarned > 0
                ? l10n.dailyResultSnippetCompletedAt(
                    entry.snippetNumber,
                    DateFormat.Hm().format(entry.completedAt.toLocal()),
                  )
                : l10n.dailyResultNotGuessedAt(
                    DateFormat.Hm().format(entry.completedAt.toLocal()),
                  ),
            scoreText: '${entry.pointsEarned}',
          ),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResultTrackCard(
          title: track.title,
          artist: track.artist,
          coverUrl: track.coverUrl,
          artworkSize: 132,
          padding: const EdgeInsets.all(18),
          onArtworkTap: () => _toggleResultPreview(track),
          isArtworkPlaying: _isPreviewPlaying && _previewTrackId == track.id,
          footer: isCorrect
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: AppTheme.successColor),
                      const SizedBox(width: 8),
                      Text(
                        l10n.dailyResultPointsSnippet(
                          session.pointsEarned ?? 0,
                          session.currentSnippet,
                        ),
                        style: const TextStyle(
                          color: AppTheme.successColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : null,
        ),
        const SizedBox(height: 24),
        ResultLeaderboardSection(
          title: l10n.packResultsTitle,
          emptyText: l10n.dailyResultNoOtherPlayersCompleted,
          rows: leaderboardRows,
        ),
        const SizedBox(height: 32),
        ResultChatSection(
          title: l10n.chatTitle,
          emptyTitle: l10n.chatNoMessagesYet,
          emptySubtitle: l10n.chatStartConversation,
          messages: context.watch<GameProvider>().messages,
          currentUserId: context.watch<AuthProvider>().user?.id,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  bool _shouldShowRoomChatComposer(GameProvider gameProvider) {
    final session = gameProvider.currentSession;
    return _selectedHistoryDate == null &&
        _activePackId == null &&
        session != null &&
        session.isCompleted;
  }

  bool _shouldShowPackChatComposer(PackBundleProvider packBundleProvider) {
    return _selectedHistoryDate == null &&
        _activePackId != null &&
        packBundleProvider.loadedPackId == _activePackId &&
        packBundleProvider.session?.isCompleted == true;
  }

  Widget _buildChatComposer({
    required String hintText,
    required VoidCallback onSend,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1E).withValues(alpha: 0.96),
        border: Border(
          top: BorderSide(color: AppTheme.surfaceColor.withValues(alpha: 0.6)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: hintText,
                  filled: true,
                  fillColor: AppTheme.surfaceColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                maxLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                gradient: AppTheme.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: onSend,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomChatComposer() {
    return _buildChatComposer(
      hintText: AppLocalizations.of(context).chatTypeMessageHint,
      onSend: _handleSendMessage,
    );
  }

  Widget _buildPackChatComposer(BuildContext context) {
    return _buildChatComposer(
      hintText: AppLocalizations.of(context).chatTypeMessageHint,
      onSend: _handlePackSendMessage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final roomProvider = context.watch<RoomProvider>();
    final room = roomProvider.currentRoom;
    final packProvider = context.watch<PackProvider>();
    final packBundleProvider = context.watch<PackBundleProvider>();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final allow = await _onWillPop();
        if (allow && context.mounted) {
          Navigator.of(context).pop(result);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F1E),
        appBar: AppBar(
          title: room == null
              ? const Text('Daily Challenge')
              : InkWell(
                  onTap: _openRoomDetails,
                  borderRadius: BorderRadius.circular(8),
                  child: Text(
                    room.displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          actions: [
            IconButton(
              icon: Icon(
                _showHistorySelector ? Icons.history_toggle_off : Icons.history,
              ),
              onPressed: _toggleHistorySelector,
              tooltip: _showHistorySelector
                  ? 'Hide 30-day history'
                  : 'Show 30-day history',
            ),
            IconButton(
              icon: const Icon(Icons.album),
              onPressed: room == null ? null : _openPackList,
              tooltip: 'Packs',
            ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.backgroundGradient,
          ),
          child: Consumer<GameProvider>(
            builder: (context, gameProvider, _) {
              final showRoomComposer = _shouldShowRoomChatComposer(
                gameProvider,
              );
              final showPackComposer = _shouldShowPackChatComposer(
                packBundleProvider,
              );
              final content = _selectedHistoryDate != null
                  ? _buildHistoryView()
                  : _buildActiveGameContent(
                      context,
                      gameProvider,
                      packProvider,
                    );

              return Column(
                children: [
                  Expanded(child: content),
                  if (showRoomComposer) _buildRoomChatComposer(),
                  if (showPackComposer) _buildPackChatComposer(context),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildActiveGameContent(
    BuildContext context,
    GameProvider gameProvider,
    PackProvider packProvider,
  ) {
    final l10n = AppLocalizations.of(context);
    if (gameProvider.currentSession == null) {
      return _buildLoadingSkeleton();
    }

    final session = gameProvider.currentSession!;
    final retryUnlockPending =
        session.awaitingRetryUnlock && session.retryCredits == 0;
    final interactionLocked =
        gameProvider.isLoading ||
        _retryActivationInProgress ||
        _completionAdInProgress;

    if (session.isCompleted) {
      if (!_completionRecorded && !_completionAdInProgress) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _onGameCompleted();
          }
        });
      }
      if (_completionAdInProgress) {
        return const Center(child: CircularProgressIndicator());
      }
      return SingleChildScrollView(
        controller: _contentScrollController,
        padding: AppTheme.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_showHistorySelector) ...[
              _buildDateRow(),
              const SizedBox(height: 8),
            ],
            const _NextSongCountdown(),
            const SizedBox(height: 16),
            _buildPackSwitcher(context, packProvider.ownedPacks),
            if (_activePackId == null)
              _buildResultContent(session, gameProvider.leaderboard)
            else
              PackBundleContent(
                key: ValueKey(_activePackId),
                roomId: widget.roomId,
                packId: _activePackId!,
                packName: _activePackName ?? 'Pack',
                embedInScroll: true,
              ),
          ],
        ),
      );
    }

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      controller: _contentScrollController,
      padding: AppTheme.pagePadding.copyWith(
        bottom: AppTheme.pagePadding.bottom + bottomInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_showHistorySelector) ...[
            _buildDateRow(),
            const SizedBox(height: 8),
          ],
          const _NextSongCountdown(),
          const SizedBox(height: 16),
          _buildPackSwitcher(context, packProvider.ownedPacks),
          if (_activePackId == null) ...[
            _buildSnippetTimeline(session),
            const SizedBox(height: 24),

            CompactPlaybackPanel(
              durationLabel: _formatSnippetDuration(session.snippetDuration),
              onPressed: _handlePlaySnippet,
              isPlaying: gameProvider.audioService.isPlaying,
            ),
            const SizedBox(height: 24),

            if (!retryUnlockPending) ...[
              TrackAutocomplete(
                controller: _titleController,
                hintText: l10n.packSearchSongTitleOrArtist,
                labelText: l10n.packSearchSongTitleOrArtist,
                onTrackSelected: (track) {
                  setState(() {
                    _selectedTrack = track;
                  });
                },
              ),
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: session.currentSnippet >= 6
                          ? null
                          : interactionLocked
                          ? null
                          : _handleSkip,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary,
                        side: const BorderSide(color: AppTheme.textSecondary),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.borderRadius,
                          ),
                        ),
                      ),
                      child: Text(l10n.gameSkip),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: GradientButton(
                      text: l10n.gameSubmitGuess,
                      onPressed: interactionLocked ? null : _handleGuess,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const SizedBox(height: 24),
            ],

            if (session.currentSnippet >= 6 && !session.isCompleted) ...[
              _buildRetryCard(session),
              const SizedBox(height: 24),
            ],

            // Hints
            _buildHintsSection(context, gameProvider),
          ] else
            PackBundleContent(
              key: ValueKey(_activePackId),
              roomId: widget.roomId,
              packId: _activePackId!,
              packName: _activePackName ?? 'Pack',
              embedInScroll: true,
            ),
        ],
      ),
    );
  }

  Widget _buildSnippetTimeline(GameSession session) {
    final totalWeight = _snippetTimelineWeights.fold<double>(
      0,
      (sum, weight) => sum + weight,
    );

    return SizedBox(
      height: 22,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boundaries = <double>[0];
          var consumedWidth = 0.0;

          for (final weight in _snippetTimelineWeights) {
            consumedWidth += constraints.maxWidth * (weight / totalWeight);
            boundaries.add(consumedWidth);
          }

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: Container(
                  height: 2,
                  color: AppTheme.textSecondary.withValues(alpha: 0.25),
                ),
              ),
              Positioned(
                top: 10,
                left: 0,
                width: boundaries[session.currentSnippet],
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  height: _skipFeedbackActive ? 5 : 4,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.22),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
              for (var index = 0; index < boundaries.length; index++)
                Positioned(
                  left: (boundaries[index] - 1).clamp(
                    0,
                    constraints.maxWidth - 2,
                  ),
                  top: 4,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    width: index < session.currentSnippet - 1 ? 0 : 2,
                    height: index == session.currentSnippet
                        ? (_skipFeedbackActive ? 16 : 14)
                        : 12,
                    decoration: BoxDecoration(
                      color: index < session.currentSnippet - 1
                          ? Colors.transparent
                          : index == session.currentSnippet
                          ? AppTheme.primaryColor
                          : index == session.currentSnippet - 1
                          ? Colors.transparent
                          : AppTheme.textSecondary.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRetryCard(GameSession session) {
    final l10n = AppLocalizations.of(context);
    if (session.retryCredits > 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.successColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
          border: Border.all(
            color: AppTheme.successColor.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          l10n.gameRetryUnlocked,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppTheme.successColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (!session.retryAvailable) {
      return const SizedBox.shrink();
    }

    final nextAction = session.nextRetryRequirement;
    final isAdAction = nextAction == 'ad';
    final retryCost = session.retryCostCoins ?? 120;
    final buttonLabel = isAdAction
        ? l10n.gameWatchAdForRetry
        : l10n.gameSpendCoinsForFinalChance(retryCost);
    final subtitle = isAdAction
        ? l10n.gameRetryWatchAdSubtitle
        : l10n.gameRetryUseCoinsSubtitle;
    final hasNoAds = context.watch<AuthProvider>().user?.hasNoAds ?? false;
    final ctaLabel = isAdAction
        ? (hasNoAds ? l10n.gameUseRewardForSecondChance : buttonLabel)
        : buttonLabel;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.gameExtraChanceTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _retryActivationInProgress
                ? null
                : () => _handleActivateRetry(isAdAction ? 'ad' : 'coins'),
            child: Text(_retryActivationInProgress ? l10n.loading : ctaLabel),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _retryActivationInProgress
                ? null
                : () => _handleActivateRetry('forfeit'),
            child: Text(l10n.gameSkipExtraChanceShowResults),
          ),
        ],
      ),
    );
  }

  // ── Hints ───────────────────────────────────────────────────────────────

  // Hints are sequential: Genre (30) -> Decade (60) -> Artist (100)
  static const _hintOrder = [
    {'type': 'genre', 'cost': 30},
    {'type': 'decade', 'cost': 60},
    {'type': 'artist_name', 'cost': 100},
  ];

  String _hintLabel(AppLocalizations l10n, String hintType) {
    switch (hintType) {
      case 'genre':
        return l10n.gameHintGenre;
      case 'decade':
        return l10n.gameHintDecade;
      case 'artist_name':
        return l10n.gameHintArtist;
      default:
        return hintType;
    }
  }

  Widget _buildHintsSection(BuildContext context, GameProvider gameProvider) {
    final l10n = AppLocalizations.of(context);
    final hintValues = gameProvider.hintValues;

    // Find the index of the next unlockable hint (first one not yet purchased)
    final nextIndex = _hintOrder.indexWhere(
      (h) => !hintValues.containsKey(h['type']),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.gameHintsTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Row(
          children: _hintOrder.asMap().entries.map((entry) {
            final i = entry.key;
            final hint = entry.value;
            final hintType = hint['type'] as String;
            final revealedValue = hintValues[hintType];
            final isNextToBuy = i == nextIndex;
            final isLocked = revealedValue == null && !isNextToBuy;
            final label = _hintLabel(l10n, hintType);

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: i == 0 ? 0 : 6,
                  right: i == _hintOrder.length - 1 ? 0 : 6,
                ),
                child: _buildHintButton(
                  context: context,
                  gameProvider: gameProvider,
                  hintType: hintType,
                  label: label,
                  cost: hint['cost'] as int,
                  revealedValue: revealedValue,
                  revealedLabel: label,
                  isLocked: isLocked,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildHintButton({
    required BuildContext context,
    required GameProvider gameProvider,
    required String hintType,
    required String label,
    required int cost,
    required String? revealedValue,
    required String revealedLabel,
    required bool isLocked,
  }) {
    if (revealedValue != null) {
      // Purchased — show the revealed value
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
          border: Border.all(color: AppTheme.primaryColor, width: 1),
        ),
        child: Column(
          children: [
            Text(
              revealedLabel,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.primaryColor),
            ),
            const SizedBox(height: 4),
            Text(
              revealedValue,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (isLocked) {
      // Not yet unlockable — greyed out
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor.withOpacity(0.4),
          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
          border: Border.all(
            color: AppTheme.textSecondary.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.lock_outline,
              size: 16,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Available to purchase
    return OutlinedButton(
      onPressed: () => _handlePurchaseHint(context, gameProvider, hintType),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.textPrimary,
        side: const BorderSide(color: AppTheme.textSecondary),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
        ),
      ),
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 2),
          Text(
            '🪙 $cost',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.primaryColor),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePurchaseHint(
    BuildContext context,
    GameProvider gameProvider,
    String hintType,
  ) async {
    try {
      final response = await gameProvider.purchaseHint(
        roomId: widget.roomId,
        hintType: hintType,
      );
      // Update coin balance in auth provider
      final newCoins = response['coins'] as int;
      if (mounted) {
        context.read<AuthProvider>().updateCoinsBalance(newCoins);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // ── Date row ────────────────────────────────────────────────────────────

  Widget _buildDateRow() {
    final gameProvider = context.read<GameProvider>();
    final activeDate = _activeGameDate();
    final dates = List.generate(
      31,
      (i) => activeDate.subtract(Duration(days: 30 - i)),
    );

    return SizedBox(
      height: 76,
      child: ListView.builder(
        controller: _dateScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: dates.length,
        itemBuilder: (context, index) {
          final date = dates[index];
          final dateStr = DateFormat('yyyy-MM-dd').format(date);
          final isToday = index == dates.length - 1;
          final isSelected = isToday
              ? _selectedHistoryDate == null
              : _selectedHistoryDate == dateStr;

          // Result dot color
          Color? dotColor;
          if (_activePackId != null) {
            // Pack mode: show pack bundle session result
            if (!isToday) {
              final packDay = _packHistoryMap[dateStr];
              if (packDay?.mySession != null) {
                dotColor = packDay!.mySession!.completed
                    ? AppTheme.successColor
                    : AppTheme.errorColor;
              }
            }
          } else if (isToday) {
            final session = gameProvider.currentSession;
            if (session != null && session.isCompleted) {
              dotColor = session.correctGuess
                  ? AppTheme.successColor
                  : AppTheme.errorColor;
            }
          } else {
            final histDay = _historyMap[dateStr];
            if (histDay?.mySession != null) {
              dotColor = histDay!.mySession!.correctGuess
                  ? AppTheme.successColor
                  : AppTheme.errorColor;
            }
          }

          return GestureDetector(
            onTap: () => isToday ? _selectDate(null) : _selectDate(dateStr),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 6),
              width: 48,
              decoration: BoxDecoration(
                gradient: isSelected ? AppTheme.primaryGradient : null,
                color: isSelected ? null : AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    DateFormat('MMM').format(date),
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected
                          ? Colors.white70
                          : AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor ?? Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── History view ─────────────────────────────────────────────────────────

  Widget _buildHistoryView() {
    if (_historyDetailLoading) {
      return _buildHistoryStateContainer(
        const CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }
    if (_activePackId != null) {
      if (_packHistoryDetail == null) {
        return _buildHistoryStateContainer(
          Text(
            'Could not load data',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
          ),
        );
      }
      return _buildPackHistoryContent(_packHistoryDetail!);
    }
    if (_historyDetail == null) {
      return _buildHistoryStateContainer(
        Text(
          'Could not load data',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
        ),
      );
    }
    return _buildHistoryContent(_historyDetail!);
  }

  Widget _buildHistoryStateContainer(Widget child) {
    return SingleChildScrollView(
      padding: AppTheme.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_showHistorySelector) ...[
            _buildDateRow(),
            const SizedBox(height: 8),
          ],
          SizedBox(height: 280, child: Center(child: child)),
        ],
      ),
    );
  }

  Widget _buildHistoryContent(HistoryDayDetail detail) {
    final session = detail.mySession;
    final leaderboardRows = detail.leaderboard
        .map(
          (entry) => ResultLeaderboardRowData(
            title: entry.username,
            subtitle:
                'Snippet ${entry.snippetNumber}'
                '${entry.completedAt != null ? ' · ${DateFormat.Hm().format(entry.completedAt!.toLocal())}' : ''}',
            scoreText: '${entry.pointsEarned}',
          ),
        )
        .toList();

    return _buildSharedHistoryContent(
      track: detail.track,
      footer: _buildHistoryStatusFooter(
        isSuccess: session?.correctGuess,
        successText: session == null
            ? null
            : '+${session.pointsEarned ?? 0} pts · Snippet ${session.currentSnippet}',
        failureText: 'Not guessed',
        emptyText: 'You didn\'t play this day',
      ),
      leaderboardRows: leaderboardRows,
      leaderboardEmptyText: 'Nobody guessed this day',
      messages: _mapHistoryMessages(detail.messages),
    );
  }

  Widget _buildPackHistoryContent(PackHistoryDayDetail detail) {
    final session = detail.mySession;
    final leaderboardRows = detail.leaderboard
        .map(
          (entry) => ResultLeaderboardRowData(
            title: entry.username,
            subtitle:
                'Stage ${entry.stageNumber} · ${DateFormat.Hm().format(entry.completedAt.toLocal())}',
            scoreText: '${entry.pointsEarned}',
          ),
        )
        .toList();

    return _buildSharedHistoryContent(
      track: detail.track,
      footer: _buildHistoryStatusFooter(
        isSuccess: session?.completed,
        successText: session == null
            ? null
            : '+${session.pointsEarned} pts · Stage ${session.currentStage}',
        failureText: 'Not completed',
        emptyText: 'You didn\'t play this pack that day',
      ),
      leaderboardRows: leaderboardRows,
      leaderboardEmptyText: 'Nobody completed this pack that day',
      messages: _mapHistoryMessages(detail.messages),
    );
  }

  Widget _buildSharedHistoryContent({
    required HistoryTrack track,
    required Widget footer,
    required List<ResultLeaderboardRowData> leaderboardRows,
    required String leaderboardEmptyText,
    required List<Message> messages,
  }) {
    final currentUserId = context.read<AuthProvider>().user?.id;

    return SingleChildScrollView(
      padding: AppTheme.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_showHistorySelector) ...[
            _buildDateRow(),
            const SizedBox(height: 8),
          ],
          ResultTrackCard(
            title: track.title,
            artist: track.artist,
            coverUrl: track.coverUrl,
            artworkSize: 160,
            padding: const EdgeInsets.all(24),
            footer: footer,
          ),
          const SizedBox(height: 24),
          ResultLeaderboardSection(
            title: 'Results',
            emptyText: leaderboardEmptyText,
            rows: leaderboardRows,
          ),
          const SizedBox(height: 24),
          ResultChatSection(
            title: 'Chat',
            emptyTitle: 'No messages that day',
            messages: messages,
            currentUserId: currentUserId,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildHistoryStatusFooter({
    required bool? isSuccess,
    required String? successText,
    required String failureText,
    required String emptyText,
  }) {
    if (isSuccess == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          emptyText,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
          textAlign: TextAlign.center,
        ),
      );
    }

    final color = isSuccess ? AppTheme.successColor : AppTheme.errorColor;
    final icon = isSuccess ? Icons.check_circle : Icons.cancel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            isSuccess ? successText! : failureText,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  List<Message> _mapHistoryMessages(List<HistoryMessage> messages) {
    return messages
        .map(
          (message) => Message(
            id: message.id,
            user: User(
              id: message.userId,
              email: '',
              username: message.username,
            ),
            message: message.message,
            createdAt: message.createdAt,
          ),
        )
        .toList();
  }
}

/// Countdown widget showing time remaining until the next daily song (12:00 UTC).
class _NextSongCountdown extends StatefulWidget {
  const _NextSongCountdown();

  @override
  State<_NextSongCountdown> createState() => _NextSongCountdownState();
}

class _NextSongCountdownState extends State<_NextSongCountdown> {
  late Timer _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = _timeUntilNoonUtc();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _remaining = _timeUntilNoonUtc());
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Duration _timeUntilNoonUtc() {
    final now = DateTime.now().toUtc();
    var next = DateTime.utc(now.year, now.month, now.day, 12);
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }
    return next.difference(now);
  }

  @override
  Widget build(BuildContext context) {
    final h = _remaining.inHours.toString().padLeft(2, '0');
    final m = (_remaining.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_remaining.inSeconds % 60).toString().padLeft(2, '0');

    return Text.rich(
      TextSpan(
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
        children: [
          const TextSpan(text: 'Next song in '),
          TextSpan(
            text: '$h:$m:$s',
            style: const TextStyle(
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
