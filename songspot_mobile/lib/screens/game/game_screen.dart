import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/app_theme.dart';
import '../../config/admob_config.dart';
import '../../config/daily_mode_localization.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/room_provider.dart';
import '../../models/track.dart';
import '../../models/pack.dart';
import '../../models/game_session.dart';
import '../../models/message.dart';
import '../../models/user.dart';
import '../../models/room.dart';
import '../../widgets/compact_playback_panel.dart';
import '../../widgets/daily_mode_card.dart';
import '../../widgets/result_chat_section.dart';
import '../../widgets/result_leaderboard_section.dart';
import '../../widgets/result_track_card.dart';
import '../../widgets/track_autocomplete.dart';
import '../../widgets/gradient_button.dart';
import '../../services/api_service.dart';
import '../../services/admob_service.dart';
import '../../services/audio_service.dart';
import '../../services/websocket_service.dart';
import '../../models/history_day.dart';
import '../packs/pack_bundle_screen.dart';
import '../packs/pack_list_screen.dart';
import '../room/room_detail_screen.dart';

class GameScreen extends StatefulWidget {
  final String roomId;

  const GameScreen({super.key, required this.roomId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

enum _GameScreenMenuAction { roomDetails, packs }

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  static const String _dailyModeMix = 'mix';
  static const String _dailyModeGenre = 'genre';
  static const String _dailyModeDecade = 'decade';
  static const String _dailyModeHardcore = 'hardcore';
  static const String _roomModePack = 'pack';
  static const List<double> _snippetTimelineWeights = [1, 1, 2, 3, 4, 5];
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _contentScrollController = ScrollController();
  final _dateScrollController = ScrollController();
  final AudioService _previewAudioService = AudioService();
  Track? _selectedTrack;
  late GameProvider _gameProvider;
  bool _pendingChatAutoScroll = false;
  int _lastKnownMessageCount = 0;
  bool _isPreviewPlaying = false;
  int _previewPlaybackRequestId = 0;
  String? _previewTrackId;
  StreamSubscription<WebSocketEvent>? _roomModeSubscription;

  // History
  final _apiService = ApiService();
  String? _selectedHistoryDate; // null = active game (today)
  Map<String, HistoryDay> _historyMap = {};
  final Map<String, Map<String, HistoryDay>> _historyCacheByMode = {};
  Map<String, PackHistoryDay> _packHistoryMap = {};
  HistoryDayDetail? _historyDetail;
  final Map<String, Map<String, HistoryDayDetail>> _historyDetailCacheByMode =
      {};
  PackHistoryDayDetail? _packHistoryDetail;
  bool _historyDetailLoading = false;
  bool _packHistoryDetailLoading = false;
  String _activeDailyMode = _dailyModeMix;
  String _activeRoomMode = _dailyModeMix;
  final Map<String, bool> _completionRecordedByMode = {};
  final Map<String, int> _completionAdAttemptsByMode = {};
  bool _completionAdInProgress = false;
  bool _retryActivationInProgress = false;
  bool _showHistorySelector = false;
  Timer? _resultRefreshTimer;
  Timer? _skipFeedbackTimer;
  bool _skipFeedbackActive = false;
  bool _isModeSwitching = false;
  bool _isModeRefreshing = false;
  GameSession? _modeTransitionSession;
  List<LeaderboardEntry> _modeTransitionLeaderboard = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gameProvider = context.read<GameProvider>();
    final roomProvider = context.read<RoomProvider>();
    final authProvider = context.read<AuthProvider>();
    _lastKnownMessageCount = _gameProvider.messages.length;
    _gameProvider.addListener(_handleGameProviderUpdate);
    _roomModeSubscription = _gameProvider.webSocketEvents.listen(
      _handleRoomModeEvent,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final restored = _gameProvider.restoreCachedModeState(
        widget.roomId,
        mode: _activeDailyMode,
      );
      if (restored && mounted) {
        setState(() {
          _historyMap = _cachedHistoryMapForMode(_activeDailyMode);
        });
      }
      if (mounted) {
        setState(() {
          _isModeSwitching = !restored;
          _isModeRefreshing = restored;
        });
      }
      await _refreshDailyMode(mode: _activeDailyMode, useCachedState: restored);
      // Load room details for name and host info
      roomProvider.loadRoomDetails(widget.roomId);
      final adsDisabled = authProvider.user?.hasNoAds ?? false;
      unawaited(AdMobService().preloadInterstitial(adsDisabled: adsDisabled));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resultRefreshTimer?.cancel();
    _skipFeedbackTimer?.cancel();
    _roomModeSubscription?.cancel();
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

  void _handleRoomModeEvent(WebSocketEvent event) {
    if (event.type != WebSocketEventType.roomModeUpdated || !mounted) return;
    final data = event.data as Map<String, dynamic>;
    final roomId = data['room_id'] as String?;
    if (roomId != widget.roomId) return;

    final rawModes = data['daily_modes'] as List<dynamic>? ?? const [];
    final dailyModes = rawModes
        .map((item) => RoomDailyMode.fromJson(item as Map<String, dynamic>))
        .toList();
    context.read<RoomProvider>().updateRoomDailyModes(
      widget.roomId,
      dailyModes,
    );

    final actorUserId = data['actor_user_id'] as String?;
    final currentUserId = context.read<AuthProvider>().user?.id;
    final activityMessage = data['activity_message'] as String?;
    if (activityMessage != null &&
        activityMessage.isNotEmpty &&
        actorUserId != currentUserId) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(activityMessage)));
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

  Track _asPlayableTrack(HistoryTrack track) {
    return Track(
      id: track.id,
      title: track.title,
      artist: track.artist,
      previewUrl: track.previewUrl ?? '',
      coverUrl: track.coverUrl,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
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
    await gameProvider.skipSnippet(widget.roomId, mode: _activeDailyMode);
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
      mode: _activeDailyMode,
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
    if (_completionRecordedForActiveMode || _completionAdInProgress) return;

    final gameProvider = context.read<GameProvider>();
    if (_completionAdAttemptsForActiveMode == 0) {
      // Refresh leaderboard and load messages once when game is completed
      gameProvider.loadLeaderboard(widget.roomId, mode: _activeDailyMode);
      gameProvider.loadMessages(widget.roomId, mode: _activeDailyMode);
      _startResultRefreshTimer();
    }

    _completionAdAttemptsByMode[_activeDailyMode] =
        _completionAdAttemptsForActiveMode + 1;
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
    if (shown || adsDisabled || _completionAdAttemptsForActiveMode >= 2) {
      _completionRecordedByMode[_activeDailyMode] = true;
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
      _gameProvider.loadLeaderboard(
        widget.roomId,
        silent: true,
        mode: _activeDailyMode,
      );
    });
  }

  Future<bool> _onWillPop() async {
    return true;
  }

  bool get _completionRecordedForActiveMode =>
      _completionRecordedByMode[_activeDailyMode] ?? false;

  int get _completionAdAttemptsForActiveMode =>
      _completionAdAttemptsByMode[_activeDailyMode] ?? 0;

  List<RoomDailyMode> _availableDailyModes(Room? room) {
    final dailyModes = room?.dailyModes
        .where((mode) => mode.isEnabled)
        .toList();
    if (dailyModes != null && dailyModes.isNotEmpty) {
      return dailyModes;
    }
    return const [
      RoomDailyMode(
        mode: _dailyModeMix,
        label: '',
        subtitle: '',
        costCoins: 0,
        isFree: true,
        isEnabled: true,
        isUnlocked: true,
        progressCoins: 0,
        remainingCoins: 0,
        contributorCount: 0,
      ),
    ];
  }

  RoomDailyMode? _dailyModeStatus(Room? room, String mode) {
    for (final item in _availableDailyModes(room)) {
      if (item.mode == mode) return item;
    }
    return null;
  }

  IconData _dailyModeIcon(String mode) {
    switch (mode) {
      case _dailyModeGenre:
        return Icons.graphic_eq;
      case _dailyModeDecade:
        return Icons.history_edu;
      case _dailyModeHardcore:
        return Icons.whatshot;
      default:
        return Icons.shuffle;
    }
  }

  Color _dailyModeAccent(String mode) {
    switch (mode) {
      case _dailyModeGenre:
        return AppTheme.accentColor;
      case _dailyModeDecade:
        return AppTheme.secondaryColor;
      case _dailyModeHardcore:
        return AppTheme.errorColor;
      default:
        return AppTheme.primaryColor;
    }
  }

  String _dailyModeSubtitle(String mode, {String? genreName}) {
    return dailyModeLocalizedSubtitle(
      AppLocalizations.of(context),
      mode,
      laneName: genreName,
    );
  }

  bool _isHardcoreMode(String mode) => mode == _dailyModeHardcore;

  bool _activeModeSupportsHints() => !_isHardcoreMode(_activeDailyMode);

  bool _activeModeSupportsRetries() => !_isHardcoreMode(_activeDailyMode);

  Future<void> _showModeContributionDialog(RoomDailyMode mode) async {
    final l10n = AppLocalizations.of(context);
    final auth = context.read<AuthProvider>().user;
    final availableCoins = auth?.coins ?? 0;
    final maxAmount = mode.remainingCoins < availableCoins
        ? mode.remainingCoins
        : availableCoins;
    final quickPicks = _modeContributionQuickPicks(
      remainingCoins: mode.remainingCoins,
      availableCoins: availableCoins,
    );
    final suggested = quickPicks.isNotEmpty
        ? quickPicks.first.amount
        : maxAmount;
    final controller = TextEditingController(
      text: suggested > 0 ? '$suggested' : '',
    );
    var selectedAmount = suggested;
    final amount = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          scrollable: true,
          backgroundColor: AppTheme.surfaceColor,
          title: Text(
            l10n.dailyModeContributeTitle(
              dailyModeLocalizedLabel(l10n, mode.mode),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.dailyModeCoinsRemainingYouHave(
                  mode.remainingCoins,
                  availableCoins,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: mode.costCoins <= 0
                      ? 0
                      : mode.progressCoins.clamp(0, mode.costCoins) /
                            mode.costCoins,
                  color: _dailyModeAccent(mode.mode),
                  backgroundColor: AppTheme.backgroundColor,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    '${mode.progressCoins}/${mode.costCoins}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: _dailyModeAccent(mode.mode),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _ModeContributionPill(
                    icon: mode.isUnlocked
                        ? Icons.check_circle_outline
                        : Icons.monetization_on_outlined,
                    label: mode.isUnlocked
                        ? l10n.dailyModeUnlocked
                        : l10n.dailyModeContributionLeft(mode.remainingCoins),
                  ),
                ],
              ),
              if (quickPicks.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: quickPicks.map((pick) {
                    final selected = pick.amount == selectedAmount;
                    return FilterChip(
                      label: Text(
                        pick.isFill
                            ? l10n.dailyModeContributionFill
                            : l10n.dailyModeContributionQuickAmount(
                                pick.amount,
                              ),
                      ),
                      selected: selected,
                      onSelected: (_) {
                        setDialogState(() {
                          selectedAmount = pick.amount;
                          controller.text = '${pick.amount}';
                          controller.selection = TextSelection.collapsed(
                            offset: controller.text.length,
                          );
                        });
                      },
                      selectedColor: _dailyModeAccent(
                        mode.mode,
                      ).withValues(alpha: 0.24),
                      side: BorderSide(
                        color: selected
                            ? _dailyModeAccent(mode.mode).withValues(alpha: 0.6)
                            : AppTheme.textSecondary.withValues(alpha: 0.18),
                      ),
                      avatar: Icon(
                        pick.isFill
                            ? Icons.auto_fix_high_rounded
                            : Icons.add_rounded,
                        size: 18,
                        color: selected
                            ? _dailyModeAccent(mode.mode)
                            : AppTheme.textSecondary,
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                  signed: false,
                ),
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) {
                  setDialogState(() {
                    final parsed = int.tryParse(value.trim()) ?? 0;
                    selectedAmount = parsed <= 0
                        ? 0
                        : parsed > maxAmount
                        ? maxAmount
                        : parsed;
                  });
                },
                decoration: InputDecoration(
                  labelText: l10n.dailyModeCoinsToContribute,
                  filled: true,
                  fillColor: AppTheme.backgroundColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: selectedAmount > 0
                  ? () => Navigator.pop(dialogContext, selectedAmount)
                  : null,
              child: Text(l10n.dailyModeContribute),
            ),
          ],
        ),
      ),
    );

    if (amount == null || amount <= 0 || !mounted) return;
    final response = await context.read<RoomProvider>().contributeToDailyMode(
      roomId: widget.roomId,
      mode: mode.mode,
      amount: amount,
    );
    if (!mounted) return;

    if (response == null) {
      final errorMessage = context.read<RoomProvider>().errorMessage;
      if (errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage.replaceFirst('Exception: ', '')),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
      return;
    }

    final coins = response['coins'] as int?;
    if (coins != null) {
      context.read<AuthProvider>().updateCoinsBalance(coins);
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  Future<void> _openModesSheet() async {
    final initialRoom = context.read<RoomProvider>().currentRoom;
    if (initialRoom == null) return;
    final l10n = AppLocalizations.of(context);
    final scrollController = ScrollController();
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      showDragHandle: true,
      backgroundColor: AppTheme.surfaceColor,
      builder: (sheetContext) => Consumer<RoomProvider>(
        builder: (context, roomProvider, _) {
          final room = roomProvider.currentRoom ?? initialRoom;
          final modes = _availableDailyModes(room);

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.78,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.dailyModesTitle,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.commonClose,
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.dailyModesIntro,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: Scrollbar(
                        controller: scrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.only(right: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: modes
                                .map(
                                  (mode) => DailyModeCard(
                                    mode: mode,
                                    onPlay: mode.isPlayable
                                        ? () async {
                                            Navigator.pop(sheetContext);
                                            if (mode.mode != _activeDailyMode) {
                                              await _switchDailyMode(mode.mode);
                                            }
                                          }
                                        : null,
                                    onContribute: mode.isFree || mode.isUnlocked
                                        ? null
                                        : () async {
                                            await _showModeContributionDialog(
                                              mode,
                                            );
                                          },
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.swipe_vertical_rounded,
                            size: 16,
                            color: AppTheme.textSecondary.withValues(
                              alpha: 0.85,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l10n.dailyModesScrollHint,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    scrollController.dispose();
  }

  Future<void> _switchDailyMode(String mode) async {
    if ((mode == _activeDailyMode && _activeRoomMode == mode) ||
        _completionAdInProgress) {
      return;
    }

    final previousMode = _activeDailyMode;
    final previousSession = _gameProvider.currentSession;
    final previousLeaderboard = List<LeaderboardEntry>.from(
      _gameProvider.leaderboard,
    );

    await _gameProvider.stopPlayback();
    _previewPlaybackRequestId += 1;
    await _previewAudioService.stop();
    if (!mounted) return;

    final restored = _gameProvider.restoreCachedModeState(
      widget.roomId,
      mode: mode,
    );
    final cachedHistory = _cachedHistoryMapForMode(mode);
    setState(() {
      _activeDailyMode = mode;
      _activeRoomMode = mode;
      _selectedHistoryDate = null;
      _historyMap = cachedHistory;
      _historyDetail = null;
      _selectedTrack = null;
      _titleController.clear();
      _isPreviewPlaying = false;
      _previewTrackId = null;
      _historyDetailLoading = false;
      _packHistoryDetailLoading = false;
      _isModeSwitching = !restored;
      _isModeRefreshing = restored;
      _modeTransitionSession = restored ? null : previousSession;
      _modeTransitionLeaderboard = restored ? const [] : previousLeaderboard;
    });

    await _refreshDailyMode(
      mode: mode,
      useCachedState: restored,
      previousMode: previousMode,
    );
  }

  Future<void> _selectActivePackMode() async {
    final activePack = context.read<RoomProvider>().currentRoom?.activePack;
    if (activePack == null || _activeRoomMode == _roomModePack) return;

    await _gameProvider.stopPlayback();
    _previewPlaybackRequestId += 1;
    await _previewAudioService.stop();
    if (!mounted) return;

    setState(() {
      _activeRoomMode = _roomModePack;
      _selectedHistoryDate = null;
      _packHistoryDetail = null;
      _packHistoryDetailLoading = false;
      _selectedTrack = null;
      _titleController.clear();
      _isPreviewPlaying = false;
      _previewTrackId = null;
    });

    if (_showHistorySelector) {
      unawaited(_loadPackHistoryList(activePack.id));
      _scrollDateRowToDate(_selectedHistoryDate);
    }
  }

  void _handleHistoryAction() {
    final shouldShow = !_showHistorySelector;
    setState(() {
      _showHistorySelector = shouldShow;
      if (!shouldShow) {
        _selectedHistoryDate = null;
        _historyDetail = null;
        _packHistoryDetail = null;
        _historyDetailLoading = false;
        _packHistoryDetailLoading = false;
      }
    });

    if (!shouldShow) return;

    final activePack = context.read<RoomProvider>().currentRoom?.activePack;
    if (_activeRoomMode == _roomModePack && activePack != null) {
      unawaited(_loadPackHistoryList(activePack.id));
    } else {
      unawaited(_loadHistoryList(mode: _activeDailyMode));
    }
    _scrollDateRowToDate(_selectedHistoryDate);
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
    final previousActivePackId = context
        .read<RoomProvider>()
        .currentRoom
        ?.activePack
        ?.id;
    await context.read<GameProvider>().stopPlayback();
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PackListScreen(roomId: widget.roomId)),
    );
    if (!mounted) return;
    await context.read<RoomProvider>().loadRoomDetails(widget.roomId);
    if (!mounted) return;
    final nextActivePackId = context
        .read<RoomProvider>()
        .currentRoom
        ?.activePack
        ?.id;
    if (nextActivePackId != null && nextActivePackId != previousActivePackId) {
      setState(() {
        _activeRoomMode = _roomModePack;
        _selectedHistoryDate = null;
        _packHistoryMap = {};
        _packHistoryDetail = null;
        _packHistoryDetailLoading = false;
      });
      if (_showHistorySelector) {
        unawaited(_loadPackHistoryList(nextActivePackId));
        _scrollDateRowToDate(_selectedHistoryDate);
      }
    } else if (nextActivePackId == null && _activeRoomMode == _roomModePack) {
      setState(() {
        _activeRoomMode = _activeDailyMode;
        _selectedHistoryDate = null;
        _packHistoryMap = {};
        _packHistoryDetail = null;
        _packHistoryDetailLoading = false;
      });
    }
  }

  void _scrollDateRowToDate(String? dateStr) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_dateScrollController.hasClients) return;
      final maxOffset = _dateScrollController.position.maxScrollExtent;
      if (dateStr == null) {
        _dateScrollController.jumpTo(maxOffset);
        return;
      }

      final parsedDate = DateTime.tryParse(dateStr);
      if (parsedDate == null) {
        _dateScrollController.jumpTo(maxOffset);
        return;
      }

      final activeDate = _activeGameDate();
      final selectedDate = DateTime.utc(
        parsedDate.year,
        parsedDate.month,
        parsedDate.day,
      );
      final dayOffset = activeDate.difference(selectedDate).inDays;
      final index = (30 - dayOffset).clamp(0, 30);
      const itemExtent = 54.0;
      const edgePadding = 12.0;
      final itemStart = index * itemExtent;
      final itemEnd = itemStart + 48.0;
      final currentOffset = _dateScrollController.offset;
      final viewportWidth = _dateScrollController.position.viewportDimension;
      final visibleStart = currentOffset;
      final visibleEnd = currentOffset + viewportWidth;

      if (itemStart >= visibleStart + edgePadding &&
          itemEnd <= visibleEnd - edgePadding) {
        return;
      }

      double targetOffset;
      if (itemStart < visibleStart + edgePadding) {
        targetOffset = itemStart - edgePadding;
      } else {
        targetOffset = itemEnd - viewportWidth + edgePadding;
      }
      _dateScrollController.jumpTo(targetOffset.clamp(0.0, maxOffset));
    });
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
            mode: _activeDailyMode,
          );
        } else {
          final result = await AdMobService().showRewarded(
            adsDisabled: false,
            placement: RewardedPlacement.retryUnlock,
            onRewardEarned: () async {
              response = await gameProvider.activateRetry(
                roomId: widget.roomId,
                action: 'ad',
                mode: _activeDailyMode,
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
          mode: _activeDailyMode,
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

  Future<void> _loadHistoryList({
    String? mode,
    bool preferCache = false,
    bool refreshInBackground = false,
  }) async {
    final resolvedMode = mode ?? _activeDailyMode;
    final cachedHistory = _historyCacheByMode[resolvedMode];
    if (preferCache && cachedHistory != null && mounted) {
      setState(() {
        _historyMap = Map<String, HistoryDay>.from(cachedHistory);
      });
      if (!refreshInBackground) {
        return;
      }
    }

    try {
      final data = await _apiService.getRoomHistory(
        widget.roomId,
        limit: 31,
        mode: resolvedMode,
      );
      final days = (data['results'] as List)
          .map((j) => HistoryDay.fromJson(j as Map<String, dynamic>))
          .toList();
      final historyMap = {for (final day in days) day.date: day};
      _historyCacheByMode[resolvedMode] = historyMap;
      if (!mounted ||
          resolvedMode != _activeDailyMode ||
          _activeRoomMode == _roomModePack) {
        return;
      }
      setState(() {
        _historyMap = Map<String, HistoryDay>.from(historyMap);
      });
      if (_showHistorySelector &&
          _activeRoomMode != _roomModePack &&
          _selectedHistoryDate == null) {
        _scrollDateRowToDate(_selectedHistoryDate);
      }
    } catch (_) {
      // History chips are optional; fail silently
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
      final activePackId = context
          .read<RoomProvider>()
          .currentRoom
          ?.activePack
          ?.id;
      if (activePackId != packId) return;
      final days = (data['results'] as List)
          .map((j) => PackHistoryDay.fromJson(j as Map<String, dynamic>))
          .toList();
      setState(() {
        _packHistoryMap = {for (final d in days) d.date: d};
      });
      if (_showHistorySelector &&
          _activeRoomMode == _roomModePack &&
          _selectedHistoryDate == null) {
        _scrollDateRowToDate(_selectedHistoryDate);
      }
    } catch (_) {
      // History chips are optional; fail silently
    }
  }

  Future<void> _selectDate(String? dateStr) async {
    if (dateStr == _selectedHistoryDate) return;
    if (dateStr == null) {
      setState(() {
        _selectedHistoryDate = null;
        _historyDetail = null;
        _packHistoryDetail = null;
      });
      _scrollDateRowToDate(null);
      return;
    }

    final activePack = context.read<RoomProvider>().currentRoom?.activePack;
    final showingPackHistory =
        _activeRoomMode == _roomModePack && activePack != null;
    final resolvedMode = _activeDailyMode;
    final cachedHistoryDetail = showingPackHistory
        ? null
        : _historyDetailCacheByMode[resolvedMode]?[dateStr];

    setState(() {
      _selectedHistoryDate = dateStr;
      _historyDetail = cachedHistoryDetail;
      _packHistoryDetail = null;
      _historyDetailLoading =
          !showingPackHistory && cachedHistoryDetail == null;
      _packHistoryDetailLoading = showingPackHistory;
    });
    _scrollDateRowToDate(dateStr);
    try {
      if (showingPackHistory) {
        final data = await _apiService.getPackBundleHistoryDetail(
          widget.roomId,
          activePack.id,
          dateStr,
        );
        if (mounted) {
          setState(() {
            _packHistoryDetail = PackHistoryDayDetail.fromJson(data);
            _historyDetailLoading = false;
            _packHistoryDetailLoading = false;
          });
          _scrollDateRowToDate(dateStr);
        }
        return;
      }
      final data = await _apiService.getRoomHistoryDetail(
        widget.roomId,
        dateStr,
        mode: resolvedMode,
      );
      final historyDetail = HistoryDayDetail.fromJson(data);
      _historyDetailCacheByMode.putIfAbsent(
        resolvedMode,
        () => <String, HistoryDayDetail>{},
      )[dateStr] = historyDetail;
      if (mounted) {
        if (_activeDailyMode != resolvedMode ||
            _selectedHistoryDate != dateStr ||
            _activeRoomMode == _roomModePack) {
          return;
        }
        setState(() {
          _historyDetail = historyDetail;
          _historyDetailLoading = false;
          _packHistoryDetailLoading = false;
        });
        _scrollDateRowToDate(dateStr);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _historyDetailLoading = false;
          _packHistoryDetailLoading = false;
        });
      }
    }
  }

  Future<void> _handleSendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    final currentUser = context.read<AuthProvider>().user;
    if (currentUser == null) return;

    _messageController.clear();
    _requestChatAutoScroll();
    await context.read<GameProvider>().sendMessage(
      widget.roomId,
      message,
      mode: _activeDailyMode,
      currentUser: currentUser,
    );
  }

  Future<void> _retryFailedRoomMessage(Message message) async {
    final currentUser = context.read<AuthProvider>().user;
    if (currentUser == null) return;

    _requestChatAutoScroll();
    await context.read<GameProvider>().retryMessage(
      widget.roomId,
      message,
      mode: _activeDailyMode,
      currentUser: currentUser,
    );
  }

  Widget _buildLoadingSkeleton() {
    return SingleChildScrollView(
      padding: AppTheme.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: 180,
            height: 14,
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 132,
              height: 16,
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            height: 22,
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: 72,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(AppTheme.borderRadius),
            ),
          ),
          const SizedBox(height: 24),
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
          const SizedBox(height: 28),
          Container(
            width: 120,
            height: 20,
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 84,
            decoration: BoxDecoration(
              gradient: AppTheme.cardGradient,
              borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
            ),
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
        _buildResultSummaryCard(
          title: track.title,
          artist: track.artist,
          coverUrl: track.coverUrl,
          onPlayTap: () => _toggleResultPreview(track),
          isPlaying: _isPreviewPlaying && _previewTrackId == track.id,
          statusText: isCorrect
              ? l10n.dailyResultPointsSnippet(
                  session.pointsEarned ?? 0,
                  session.currentSnippet,
                )
              : null,
          statusColor: AppTheme.successColor,
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
          onRetryFailedMessage: _retryFailedRoomMessage,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  bool _shouldShowRoomChatComposer(GameProvider gameProvider) {
    final session = gameProvider.currentSession;
    return _selectedHistoryDate == null &&
        session != null &&
        session.isCompleted;
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

  Widget _buildDailyModeSwitcher(GameSession? session) {
    final isBusy =
        context.watch<GameProvider>().isLoading ||
        _completionAdInProgress ||
        _isModeSwitching ||
        _isModeRefreshing;
    final room = context.watch<RoomProvider>().currentRoom;
    final activePack = room?.activePack;
    final playableModes = _availableDailyModes(
      room,
    ).where((mode) => mode.isPlayable).toList();
    final activeGenreName = session?.dailySong.mode != _dailyModeMix
        ? session?.dailySong.genreName
        : null;
    String subtitle;
    if (_activeRoomMode == _roomModePack && activePack != null) {
      final currentDay = activePack.currentDay;
      final totalDays = activePack.totalDays;
      subtitle = currentDay != null && totalDays > 0
          ? '${activePack.name} • Day $currentDay of $totalDays'
          : activePack.name;
    } else {
      subtitle = _dailyModeSubtitle(
        _activeDailyMode,
        genreName: _activeDailyMode == _dailyModeMix ? null : activeGenreName,
      );
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: _openModesSheet,
                  child: Text(
                    AppLocalizations.of(context).dailyModesShortLabel,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final modeButtons = <Widget>[
                ...playableModes.map(
                  (mode) => _ModePillButton(
                    label: dailyModeLocalizedLabel(
                      AppLocalizations.of(context),
                      mode.mode,
                    ),
                    icon: _dailyModeIcon(mode.mode),
                    isSelected: _activeRoomMode == mode.mode,
                    accent: _dailyModeAccent(mode.mode),
                    onTap: isBusy ? null : () => _switchDailyMode(mode.mode),
                  ),
                ),
                if (activePack != null)
                  _ModePillButton(
                    label: AppLocalizations.of(context).packModeLabel,
                    icon: Icons.library_music_rounded,
                    isSelected: _activeRoomMode == _roomModePack,
                    accent: AppTheme.secondaryColor,
                    onTap: _completionAdInProgress
                        ? null
                        : _selectActivePackMode,
                  ),
              ];
              final maxColumns = constraints.maxWidth >= 520
                  ? 3
                  : constraints.maxWidth >= 320
                  ? 2
                  : 1;
              final columns = modeButtons.length < maxColumns
                  ? modeButtons.length
                  : maxColumns;
              final itemWidth =
                  (constraints.maxWidth - ((columns - 1) * 8)) / columns;

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: modeButtons
                    .map((button) => SizedBox(width: itemWidth, child: button))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roomProvider = context.watch<RoomProvider>();
    final room = roomProvider.currentRoom;
    if (_activeRoomMode == _roomModePack && room?.activePack == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _activeRoomMode = _activeDailyMode;
        });
      });
    }
    final activeModeStatus = room == null
        ? null
        : _dailyModeStatus(room, _activeDailyMode);
    if (_activeRoomMode != _roomModePack &&
        activeModeStatus != null &&
        !activeModeStatus.isPlayable &&
        _activeDailyMode != _dailyModeMix) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_switchDailyMode(_dailyModeMix));
      });
    }

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
              ? Text(AppLocalizations.of(context).dailyModeMixLabel)
              : Text(room.displayName, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              icon: Icon(
                _showHistorySelector ? Icons.history_toggle_off : Icons.history,
              ),
              onPressed: _handleHistoryAction,
              tooltip: _showHistorySelector
                  ? 'Hide 30-day history'
                  : 'Show 30-day history',
            ),
            PopupMenuButton<_GameScreenMenuAction>(
              tooltip: 'More actions',
              onSelected: (action) async {
                switch (action) {
                  case _GameScreenMenuAction.roomDetails:
                    await _openRoomDetails();
                    break;
                  case _GameScreenMenuAction.packs:
                    await _openPackList();
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _GameScreenMenuAction.roomDetails,
                  child: Text('Room details'),
                ),
                PopupMenuItem(
                  value: _GameScreenMenuAction.packs,
                  child: Text('Browse packs'),
                ),
              ],
            ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.backgroundGradient,
          ),
          child: Consumer<GameProvider>(
            builder: (context, gameProvider, _) {
              final activePack = room?.activePack;
              final showingPackMode =
                  _activeRoomMode == _roomModePack && activePack != null;
              final showingHistory = _selectedHistoryDate != null;
              final showRoomComposer =
                  !showingPackMode &&
                  !showingHistory &&
                  _shouldShowRoomChatComposer(gameProvider);
              final content = showingHistory
                  ? _buildHistoryView()
                  : showingPackMode
                  ? _buildActivePackContent(activePack)
                  : _buildActiveGameContent(context, gameProvider);

              return Column(
                children: [
                  Expanded(child: content),
                  if (showRoomComposer) _buildRoomChatComposer(),
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
  ) {
    final l10n = AppLocalizations.of(context);
    final session =
        gameProvider.currentSession ??
        (_isModeSwitching ? _modeTransitionSession : null);
    final List<LeaderboardEntry> leaderboard =
        gameProvider.leaderboard.isNotEmpty
        ? gameProvider.leaderboard
        : (_isModeSwitching
              ? _modeTransitionLeaderboard
              : const <LeaderboardEntry>[]);

    if (session == null) {
      return _buildLoadingSkeleton();
    }
    final retryUnlockPending =
        session.awaitingRetryUnlock && session.retryCredits == 0;
    final interactionLocked =
        gameProvider.isLoading ||
        _isModeSwitching ||
        _retryActivationInProgress ||
        _completionAdInProgress;

    if (session.isCompleted) {
      if (!_isModeSwitching &&
          !_isModeRefreshing &&
          !_completionRecordedForActiveMode &&
          !_completionAdInProgress) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _onGameCompleted();
          }
        });
      }
      if (_completionAdInProgress) {
        return const Center(child: CircularProgressIndicator());
      }
      return _buildModeTransitionContainer(
        SingleChildScrollView(
          controller: _contentScrollController,
          padding: AppTheme.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_showHistorySelector) ...[
                _buildDateRow(),
                const SizedBox(height: 8),
              ],
              _buildDailyModeSwitcher(session),
              const SizedBox(height: 16),
              const _NextSongCountdown(),
              const SizedBox(height: 24),
              _buildResultContent(session, leaderboard),
            ],
          ),
        ),
      );
    }

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return _buildModeTransitionContainer(
      SingleChildScrollView(
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
            _buildDailyModeSwitcher(session),
            const SizedBox(height: 16),
            const _NextSongCountdown(),
            const SizedBox(height: 24),
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
              const SizedBox(height: 40),
            ],

            if (session.currentSnippet >= 6 && !session.isCompleted) ...[
              if (_activeModeSupportsRetries()) ...[
                _buildRetryCard(session),
                const SizedBox(height: 24),
              ],
            ],

            if (_activeModeSupportsHints())
              _buildHintsSection(context, gameProvider)
            else
              _buildHardcoreRulesCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildHardcoreRulesCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.errorColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
        border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppLocalizations.of(context).dailyModeHardcoreRulesTitle,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppTheme.errorColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context).dailyModeHardcoreRulesBody,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildActivePackContent(SongPack activePack) {
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
          _buildDailyModeSwitcher(context.read<GameProvider>().currentSession),
          const SizedBox(height: 16),
          PackBundleContent(
            key: ValueKey('room-pack-${activePack.id}'),
            roomId: widget.roomId,
            packId: activePack.id,
            packName: activePack.name,
            embedInScroll: true,
          ),
        ],
      ),
    );
  }

  Widget _buildModeTransitionContainer(Widget child) {
    if (!_isModeSwitching && !_isModeRefreshing) return child;

    final content = _isModeSwitching
        ? AbsorbPointer(child: Opacity(opacity: 0.62, child: child))
        : child;

    return Stack(
      children: [
        content,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: LinearProgressIndicator(
            color: _dailyModeAccent(_activeDailyMode),
            backgroundColor: AppTheme.surfaceColor,
          ),
        ),
      ],
    );
  }

  Future<void> _refreshDailyMode({
    required String mode,
    required bool useCachedState,
    String? previousMode,
  }) async {
    try {
      final historyFuture = _loadHistoryList(
        mode: mode,
        preferCache: useCachedState,
        refreshInBackground: true,
      );
      final sessionFuture = _gameProvider.startGameSession(
        widget.roomId,
        mode: mode,
        clearVisibleState: !useCachedState,
      );
      final leaderboardFuture = _gameProvider.loadLeaderboard(
        widget.roomId,
        mode: mode,
        silent: useCachedState,
      );
      final chatFuture = _gameProvider.connectToChat(widget.roomId, mode: mode);

      await Future.wait([
        sessionFuture,
        leaderboardFuture,
        chatFuture,
        historyFuture,
      ]);
      if (!mounted) return;
      if (_gameProvider.currentSession?.isCompleted ?? false) {
        await _gameProvider.loadMessages(widget.roomId, mode: mode);
        _startResultRefreshTimer();
      }
    } catch (e) {
      if (!mounted) return;
      if (!useCachedState && previousMode != null) {
        _gameProvider.restoreCachedModeState(widget.roomId, mode: previousMode);
        setState(() {
          _activeDailyMode = previousMode;
          _activeRoomMode = previousMode;
          _historyMap = _cachedHistoryMapForMode(previousMode);
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isModeSwitching = false;
          _isModeRefreshing = false;
          _modeTransitionSession = null;
          _modeTransitionLeaderboard = const [];
        });
      }
    }
  }

  Map<String, HistoryDay> _cachedHistoryMapForMode(String mode) {
    return Map<String, HistoryDay>.from(_historyCacheByMode[mode] ?? const {});
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
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeInOutCubic,
                  width: boundaries[session.currentSnippet],
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
          color: AppTheme.primaryColor.withValues(alpha: 0.15),
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
          color: AppTheme.surfaceColor.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
          border: Border.all(
            color: AppTheme.textSecondary.withValues(alpha: 0.3),
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
    final authProvider = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final response = await gameProvider.purchaseHint(
        roomId: widget.roomId,
        hintType: hintType,
        mode: _activeDailyMode,
      );
      if (!mounted) return;
      // Update coin balance in auth provider
      final newCoins = response['coins'] as int;
      authProvider.updateCoinsBalance(newCoins);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  List<_ModeContributionQuickPick> _modeContributionQuickPicks({
    required int remainingCoins,
    required int availableCoins,
  }) {
    final maxAmount = remainingCoins < availableCoins
        ? remainingCoins
        : availableCoins;
    if (maxAmount <= 0) return const [];

    final picks = <_ModeContributionQuickPick>[];
    for (final candidate in [10, 20]) {
      if (candidate <= 0 || candidate >= maxAmount) continue;
      picks.add(_ModeContributionQuickPick(amount: candidate));
    }
    picks.add(_ModeContributionQuickPick(amount: maxAmount, isFill: true));
    return picks;
  }

  // ── Date row ────────────────────────────────────────────────────────────

  Widget _buildDateRow() {
    final gameProvider = context.read<GameProvider>();
    final showingPackHistory =
        _activeRoomMode == _roomModePack &&
        context.read<RoomProvider>().currentRoom?.activePack != null;
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

          Color? dotColor;
          if (showingPackHistory) {
            final histDay = _packHistoryMap[dateStr];
            if (histDay?.mySession != null) {
              dotColor = histDay!.mySession!.completed
                  ? AppTheme.successColor
                  : AppTheme.primaryColor;
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
    final showingPackHistory =
        _activeRoomMode == _roomModePack &&
        context.read<RoomProvider>().currentRoom?.activePack != null;
    if (showingPackHistory) {
      if (_packHistoryDetailLoading) {
        return _buildHistoryStateContainer(
          const CircularProgressIndicator(color: AppTheme.primaryColor),
        );
      }
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
    if (_historyDetailLoading) {
      return _buildHistoryStateContainer(
        const CircularProgressIndicator(color: AppTheme.primaryColor),
      );
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
    final session = context.read<GameProvider>().currentSession;
    return SingleChildScrollView(
      padding: AppTheme.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_showHistorySelector) ...[
            _buildDateRow(),
            const SizedBox(height: 8),
          ],
          _buildDailyModeSwitcher(session),
          const SizedBox(height: 16),
          SizedBox(height: 280, child: Center(child: child)),
        ],
      ),
    );
  }

  Widget _buildHistoryContent(HistoryDayDetail detail) {
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
      allowTrackPlayback: (detail.track.previewUrl?.trim().isNotEmpty ?? false),
      leaderboardRows: leaderboardRows,
      leaderboardEmptyText: 'Nobody guessed this day',
      messages: _mapHistoryMessages(detail.messages),
    );
  }

  Widget _buildPackHistoryContent(PackHistoryDayDetail detail) {
    final leaderboardRows = detail.leaderboard
        .map(
          (entry) => ResultLeaderboardRowData(
            title: entry.username,
            subtitle: entry.pointsEarned > 0
                ? 'Stage ${entry.stageNumber}'
                      ' · ${DateFormat.Hm().format(entry.completedAt.toLocal())}'
                : AppLocalizations.of(context).dailyResultNotGuessedAt(
                    DateFormat.Hm().format(entry.completedAt.toLocal()),
                  ),
            scoreText: '${entry.pointsEarned}',
          ),
        )
        .toList();

    return _buildSharedHistoryContent(
      track: detail.track,
      allowTrackPlayback: false,
      leaderboardRows: leaderboardRows,
      leaderboardEmptyText: 'Nobody finished this stage',
      messages: _mapHistoryMessages(detail.messages),
    );
  }

  Widget _buildSharedHistoryContent({
    required HistoryTrack track,
    required bool allowTrackPlayback,
    required List<ResultLeaderboardRowData> leaderboardRows,
    required String leaderboardEmptyText,
    required List<Message> messages,
  }) {
    final currentUserId = context.read<AuthProvider>().user?.id;
    final session = context.read<GameProvider>().currentSession;

    return SingleChildScrollView(
      padding: AppTheme.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_showHistorySelector) ...[
            _buildDateRow(),
            const SizedBox(height: 8),
          ],
          _buildDailyModeSwitcher(session),
          const SizedBox(height: 16),
          ResultTrackCard(
            title: track.title,
            artist: track.artist,
            coverUrl: track.coverUrl,
            artworkSize: 152,
            padding: const EdgeInsets.all(22),
            onArtworkTap: allowTrackPlayback
                ? () => _toggleResultPreview(_asPlayableTrack(track))
                : null,
            isArtworkPlaying: allowTrackPlayback && _previewTrackId == track.id,
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

  Widget _buildResultSummaryCard({
    required String title,
    required String artist,
    required String? coverUrl,
    required Color statusColor,
    String? statusText,
    VoidCallback? onPlayTap,
    bool isPlaying = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildResultArtwork(
            coverUrl: coverUrl,
            onTap: onPlayTap,
            isPlaying: isPlaying,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    height: 1.05,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  artist,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (statusText != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultArtwork({
    required String? coverUrl,
    required VoidCallback? onTap,
    required bool isPlaying,
  }) {
    final artwork = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: coverUrl != null
          ? Image.network(
              coverUrl,
              width: 104,
              height: 104,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _buildResultArtworkFallback(),
            )
          : _buildResultArtworkFallback(),
    );

    if (onTap == null) return artwork;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          artwork,
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultArtworkFallback() {
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(
        Icons.album_rounded,
        size: 40,
        color: AppTheme.primaryColor,
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

class _ModePillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color accent;
  final VoidCallback? onTap;

  const _ModePillButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withValues(alpha: 0.18)
                : AppTheme.surfaceColor.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? accent.withValues(alpha: 0.6)
                  : AppTheme.textSecondary.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? accent : AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: isSelected
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeContributionPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ModeContributionPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeContributionQuickPick {
  final int amount;
  final bool isFill;

  const _ModeContributionQuickPick({required this.amount, this.isFill = false});
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
