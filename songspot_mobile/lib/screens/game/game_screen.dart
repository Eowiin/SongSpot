import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/app_theme.dart';
import '../../providers/game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/room_provider.dart';
import '../../providers/pack_provider.dart';
import '../../models/track.dart';
import '../../models/game_session.dart';
import '../../models/pack.dart';
import '../../widgets/track_autocomplete.dart';
import '../../widgets/gradient_button.dart';
import '../../services/api_service.dart';
import '../../services/admob_service.dart';
import '../../models/history_day.dart';
import '../packs/pack_list_screen.dart';
import '../packs/pack_bundle_screen.dart';

class GameScreen extends StatefulWidget {
  final String roomId;

  const GameScreen({super.key, required this.roomId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _chatScrollController = ScrollController();
  final _dateScrollController = ScrollController();
  Track? _selectedTrack;
  String? _activePackId;
  String? _activePackName;
  late GameProvider _gameProvider;

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

  @override
  void initState() {
    super.initState();
    _gameProvider = context.read<GameProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gameProvider.startGameSession(widget.roomId);
      _gameProvider.loadLeaderboard(widget.roomId);
      _gameProvider.connectToChat(widget.roomId);
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
    _gameProvider.disconnectFromChat();
    _titleController.dispose();
    _messageController.dispose();
    _chatScrollController.dispose();
    _dateScrollController.dispose();
    super.dispose();
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

  Future<void> _handleSkip() async {
    final gameProvider = context.read<GameProvider>();
    await gameProvider.skipSnippet(widget.roomId);
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

    final isCorrect = await gameProvider.submitGuess(
      roomId: widget.roomId,
      trackId: _selectedTrack!.id,
    );

    if (mounted) {
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
        unawaited(AdMobService().preloadRewarded(adsDisabled: adsDisabled));
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
      roomId: widget.roomId,
      gameDate: session.dailySong.date,
    );
    if (!shown && !adsDisabled) {
      await AdMobService().preloadInterstitial(adsDisabled: false);
    }
    if (shown || adsDisabled || _completionAdAttempts >= 2) {
      _completionRecorded = true;
    }
    unawaited(AdMobService().preloadRewarded(adsDisabled: adsDisabled));
    if (mounted) {
      setState(() => _completionAdInProgress = false);
    }
  }

  Future<bool> _onWillPop() async {
    return true;
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
          final rewarded = await AdMobService().showRewarded(
            adsDisabled: false,
            onRewardEarned: () async {
              response = await gameProvider.activateRetry(
                roomId: widget.roomId,
                action: 'ad',
              );
            },
          );
          if (!rewarded) {
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
                onSelected: (_) {
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
                    onSelected: (_) {
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
      // Scroll to bottom after sending message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chatScrollController.hasClients) {
          _chatScrollController.animateTo(
            _chatScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _showRenameDialog() async {
    final roomProvider = context.read<RoomProvider>();
    final room = roomProvider.currentRoom;
    if (room == null) return;

    final nameController = TextEditingController(text: room.name ?? '');

    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Rename Room'),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            hintText: 'Enter room name',
            filled: true,
            fillColor: AppTheme.backgroundColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          autofocus: true,
          maxLength: 50,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    // Don't manually dispose nameController - it will be garbage collected
    // Disposing it here causes errors as the dialog may still be referencing it during teardown

    if (newName != null && mounted) {
      final result = await roomProvider.renameRoom(
        widget.roomId,
        newName.isEmpty ? null : newName,
      );

      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Room renamed successfully'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      } else if (roomProvider.errorMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(roomProvider.errorMessage!),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
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
    final track = session.dailySong.track;
    final isCorrect = session.correctGuess;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Result Header
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: AppTheme.cardGradient,
            borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
          ),
          child: Column(
            children: [
              // Cover Image
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: track.coverUrl != null
                    ? Image.network(
                        track.coverUrl!,
                        width: 200,
                        height: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 200,
                          height: 200,
                          color: AppTheme.surfaceColor,
                          child: const Icon(
                            Icons.album,
                            size: 80,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      )
                    : Container(
                        width: 200,
                        height: 200,
                        color: AppTheme.surfaceColor,
                        child: const Icon(
                          Icons.album,
                          size: 80,
                          color: AppTheme.primaryColor,
                        ),
                      ),
              ),
              const SizedBox(height: 20),

              // Song Info
              Text(
                track.title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                track.artist,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Result Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isCorrect
                      ? AppTheme.successColor.withValues(alpha: 0.2)
                      : AppTheme.errorColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isCorrect ? Icons.check_circle : Icons.cancel,
                      color: isCorrect
                          ? AppTheme.successColor
                          : AppTheme.errorColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isCorrect
                          ? '+${session.pointsEarned} points (Snippet ${session.currentSnippet})'
                          : 'Not guessed',
                      style: TextStyle(
                        color: isCorrect
                            ? AppTheme.successColor
                            : AppTheme.errorColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Today's Results Section
        Text(
          'Today\'s Results',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 16),

        if (leaderboard.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
            ),
            child: Text(
              'No other players have guessed yet',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          )
        else
          ...leaderboard.asMap().entries.map((entry) {
            final index = entry.key;
            final leaderboardEntry = entry.value;
            final rank = index + 1;

            Color rankColor;
            if (rank == 1) {
              rankColor = const Color(0xFFFFD700); // Gold
            } else if (rank == 2) {
              rankColor = const Color(0xFFC0C0C0); // Silver
            } else if (rank == 3) {
              rankColor = const Color(0xFFCD7F32); // Bronze
            } else {
              rankColor = AppTheme.textSecondary;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
              ),
              child: Row(
                children: [
                  // Rank
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: rankColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: rankColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // User Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          leaderboardEntry.user.username,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'Snippet ${leaderboardEntry.snippetNumber} - ${DateFormat.Hm().format(leaderboardEntry.completedAt.toLocal())}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),

                  // Points
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${leaderboardEntry.pointsEarned}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        const SizedBox(height: 32),

        // Chat Section
        Text('Chat', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        _buildInlineChat(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildInlineChat() {
    final currentUserId = context.watch<AuthProvider>().user?.id;
    final gameProvider = context.watch<GameProvider>();
    final messages = gameProvider.messages;

    // Reverse to show oldest first (messages come newest first from API)
    final displayMessages = messages.take(10).toList().reversed.toList();

    return Column(
      children: [
        // Messages list with constrained height
        Container(
          constraints: const BoxConstraints(maxHeight: 300),
          child: messages.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline,
                        size: 40,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No messages yet',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Start the conversation!',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _chatScrollController,
                  shrinkWrap: true,
                  itemCount: displayMessages.length,
                  itemBuilder: (context, index) {
                    final message = displayMessages[index];
                    final isCurrentUser = message.user.id == currentUserId;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: isCurrentUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.7,
                          ),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: isCurrentUser
                                ? AppTheme.primaryGradient
                                : null,
                            color: isCurrentUser ? null : AppTheme.surfaceColor,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: isCurrentUser
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              // Always show username
                              Text(
                                isCurrentUser ? 'You' : message.user.username,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isCurrentUser
                                      ? Colors.white70
                                      : AppTheme.primaryColor,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                message.message,
                                style: TextStyle(
                                  color: isCurrentUser
                                      ? Colors.white
                                      : AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat.Hm().format(
                                  message.createdAt.toLocal(),
                                ),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isCurrentUser
                                      ? Colors.white70
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),

        const SizedBox(height: 16),

        // Message input
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
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
                onSubmitted: (_) => _handleSendMessage(),
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
                onPressed: _handleSendMessage,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final roomProvider = context.watch<RoomProvider>();
    final room = roomProvider.currentRoom;
    final currentUserId = context.watch<AuthProvider>().user?.id;
    final isHost =
        room != null && currentUserId != null && room.isHost(currentUserId);
    final packProvider = context.watch<PackProvider>();

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
          title: Text(room?.displayName ?? 'Daily Challenge'),
          actions: [
            IconButton(
              icon: const Icon(Icons.album),
              onPressed: room == null
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PackListScreen(roomId: room.id),
                        ),
                      );
                    },
              tooltip: 'Packs',
            ),
            if (isHost)
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: _showRenameDialog,
                tooltip: 'Rename room',
              ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.backgroundGradient,
          ),
          child: Consumer<GameProvider>(
            builder: (context, gameProvider, _) {
              return Column(
                children: [
                  _buildDateRow(gameProvider),
                  Expanded(
                    child: _selectedHistoryDate != null
                        ? _buildHistoryView()
                        : _buildActiveGameContent(
                            context,
                            gameProvider,
                            packProvider,
                          ),
                  ),
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
        padding: AppTheme.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
      padding: AppTheme.pagePadding.copyWith(
        bottom: AppTheme.pagePadding.bottom + bottomInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _NextSongCountdown(),
          const SizedBox(height: 16),
          _buildPackSwitcher(context, packProvider.ownedPacks),
          if (_activePackId == null) ...[
            // Progress Indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                final snippetNumber = index + 1;
                final isActive = snippetNumber == session.currentSnippet;
                final isPassed = snippetNumber < session.currentSnippet;

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isPassed
                        ? AppTheme.textSecondary
                        : isActive
                        ? AppTheme.primaryColor
                        : AppTheme.surfaceColor,
                    border: Border.all(
                      color: isActive
                          ? AppTheme.primaryColor
                          : AppTheme.textSecondary,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$snippetNumber',
                      style: TextStyle(
                        color: isPassed || isActive
                            ? Colors.white
                            : AppTheme.textSecondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 32),

            // Audio Player Card
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: AppTheme.cardGradient,
                borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.music_note,
                    size: 80,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Snippet ${session.currentSnippet}',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${session.snippetDuration}s',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${session.possiblePoints} points',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  GradientButton(
                    text: gameProvider.audioService.isPlaying
                        ? '🔊 Playing...'
                        : 'Play Snippet',
                    onPressed: gameProvider.audioService.isPlaying
                        ? null
                        : _handlePlaySnippet,
                    isLoading: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Hints
            _buildHintsSection(context, gameProvider),
            const SizedBox(height: 24),

            if (session.currentSnippet >= 6 && !session.isCompleted) ...[
              _buildRetryCard(session),
              const SizedBox(height: 24),
            ],

            if (!retryUnlockPending) ...[
              // Guess Form
              Text(
                'Make Your Guess',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              TrackAutocomplete(
                controller: _titleController,
                hintText: 'Start typing song title...',
                labelText: 'Song Title',
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
                      child: const Text('Skip'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: GradientButton(
                      text: 'Submit Guess',
                      onPressed: interactionLocked ? null : _handleGuess,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Guesses Made
              Text(
                'Guesses made: ${session.guessesMade}',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
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

  Widget _buildRetryCard(GameSession session) {
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
          'Second chance unlocked. Submit another guess.',
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
        ? 'Watch Ad for Retry'
        : 'Spend $retryCost Coins for Final Chance';
    final subtitle = isAdAction
        ? 'You reached the last snippet. Watch one rewarded ad to unlock a second chance.'
        : 'Use coins to unlock one final guess before results.';
    final hasNoAds = context.watch<AuthProvider>().user?.hasNoAds ?? false;
    final ctaLabel = isAdAction
        ? (hasNoAds ? 'Use Reward for Second Chance' : buttonLabel)
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
          Text('Extra Chance', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _retryActivationInProgress
                ? null
                : () => _handleActivateRetry(isAdAction ? 'ad' : 'coins'),
            child: Text(_retryActivationInProgress ? 'Loading...' : ctaLabel),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _retryActivationInProgress
                ? null
                : () => _handleActivateRetry('forfeit'),
            child: const Text('Skip Extra Chance and Show Results'),
          ),
        ],
      ),
    );
  }

  // ── Hints ───────────────────────────────────────────────────────────────

  // Hints are sequential: Genre (30🪙) → Decade (60🪙) → Artist (100🪙)
  static const _hintOrder = [
    {'type': 'genre', 'label': 'Genre', 'revealedLabel': 'Genre', 'cost': 30},
    {
      'type': 'decade',
      'label': 'Decade',
      'revealedLabel': 'Decade',
      'cost': 60,
    },
    {
      'type': 'artist_name',
      'label': 'Artist',
      'revealedLabel': 'Artist',
      'cost': 100,
    },
  ];

  Widget _buildHintsSection(BuildContext context, GameProvider gameProvider) {
    final hintValues = gameProvider.hintValues;

    // Find the index of the next unlockable hint (first one not yet purchased)
    final nextIndex = _hintOrder.indexWhere(
      (h) => !hintValues.containsKey(h['type']),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Hints', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Row(
          children: _hintOrder.asMap().entries.map((entry) {
            final i = entry.key;
            final hint = entry.value;
            final hintType = hint['type'] as String;
            final revealedValue = hintValues[hintType];
            final isNextToBuy = i == nextIndex;
            final isLocked = revealedValue == null && !isNextToBuy;

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
                  label: hint['label'] as String,
                  cost: hint['cost'] as int,
                  revealedValue: revealedValue,
                  revealedLabel: hint['revealedLabel'] as String,
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

  Widget _buildDateRow(GameProvider gameProvider) {
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
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }
    if (_activePackId != null) {
      if (_packHistoryDetail == null) {
        return Center(
          child: Text(
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
      return Center(
        child: Text(
          'Could not load data',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
        ),
      );
    }
    return _buildHistoryContent(_historyDetail!);
  }

  Widget _buildHistoryContent(HistoryDayDetail detail) {
    final currentUserId = context.read<AuthProvider>().user?.id;
    final session = detail.mySession;

    return SingleChildScrollView(
      padding: AppTheme.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Song card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppTheme.cardGradient,
              borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
            ),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: detail.track.coverUrl != null
                      ? Image.network(
                          detail.track.coverUrl!,
                          width: 160,
                          height: 160,
                          fit: BoxFit.cover,
                          errorBuilder: (context2, e, s) =>
                              _historyAlbumPlaceholder(),
                        )
                      : _historyAlbumPlaceholder(),
                ),
                const SizedBox(height: 16),
                Text(
                  detail.track.title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  detail.track.artist,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (session != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: session.correctGuess
                          ? AppTheme.successColor.withValues(alpha: 0.2)
                          : AppTheme.errorColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          session.correctGuess
                              ? Icons.check_circle
                              : Icons.cancel,
                          color: session.correctGuess
                              ? AppTheme.successColor
                              : AppTheme.errorColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          session.correctGuess
                              ? '+${session.pointsEarned ?? 0} pts · Snippet ${session.currentSnippet}'
                              : 'Not guessed',
                          style: TextStyle(
                            color: session.correctGuess
                                ? AppTheme.successColor
                                : AppTheme.errorColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'You didn\'t play this day',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Leaderboard
          Text('Results', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),

          if (detail.leaderboard.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
              ),
              child: Text(
                'Nobody guessed this day',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            )
          else
            ...detail.leaderboard.asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final e = entry.value;
              final rankColor = rank == 1
                  ? const Color(0xFFFFD700)
                  : rank == 2
                  ? const Color(0xFFC0C0C0)
                  : rank == 3
                  ? const Color(0xFFCD7F32)
                  : AppTheme.textSecondary;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(
                    AppTheme.cardBorderRadius,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: rankColor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$rank',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: rankColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.username,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            'Snippet ${e.snippetNumber}${e.completedAt != null ? ' · ${DateFormat.Hm().format(e.completedAt!.toLocal())}' : ''}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${e.pointsEarned}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 24),

          // Chat
          Text('Chat', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),

          if (detail.messages.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  const Icon(
                    Icons.chat_bubble_outline,
                    size: 36,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No messages that day',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          else
            ...detail.messages.map((msg) {
              final isMe = msg.userId == currentUserId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isMe
                          ? AppTheme.primaryColor.withValues(alpha: 0.2)
                          : AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (!isMe)
                          Text(
                            msg.username,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        Text(
                          msg.message,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat.Hm().format(msg.createdAt.toLocal()),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPackHistoryContent(PackHistoryDayDetail detail) {
    final currentUserId = context.read<AuthProvider>().user?.id;
    final session = detail.mySession;

    return SingleChildScrollView(
      padding: AppTheme.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Track card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppTheme.cardGradient,
              borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
            ),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: detail.track.coverUrl != null
                      ? Image.network(
                          detail.track.coverUrl!,
                          width: 160,
                          height: 160,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => _historyAlbumPlaceholder(),
                        )
                      : _historyAlbumPlaceholder(),
                ),
                const SizedBox(height: 16),
                Text(
                  detail.track.title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  detail.track.artist,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (session != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: session.completed
                          ? AppTheme.successColor.withValues(alpha: 0.2)
                          : AppTheme.errorColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          session.completed ? Icons.check_circle : Icons.cancel,
                          color: session.completed
                              ? AppTheme.successColor
                              : AppTheme.errorColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          session.completed
                              ? '+${session.pointsEarned} pts · Stage ${session.currentStage}'
                              : 'Not completed',
                          style: TextStyle(
                            color: session.completed
                                ? AppTheme.successColor
                                : AppTheme.errorColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "You didn't play this pack that day",
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Leaderboard
          Text("Results", style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),

          if (detail.leaderboard.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
              ),
              child: Text(
                'Nobody completed this pack that day',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            )
          else
            ...detail.leaderboard.asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final e = entry.value;
              final rankColor = rank == 1
                  ? const Color(0xFFFFD700)
                  : rank == 2
                  ? const Color(0xFFC0C0C0)
                  : rank == 3
                  ? const Color(0xFFCD7F32)
                  : AppTheme.textSecondary;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(
                    AppTheme.cardBorderRadius,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: rankColor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$rank',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: rankColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.username,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            'Stage ${e.stageNumber} · ${DateFormat.Hm().format(e.completedAt.toLocal())}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${e.pointsEarned}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 24),

          // Chat
          Text('Chat', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),

          if (detail.messages.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  const Icon(
                    Icons.chat_bubble_outline,
                    size: 36,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No messages that day',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          else
            ...detail.messages.map((msg) {
              final isMe = msg.userId == currentUserId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isMe
                          ? AppTheme.primaryColor.withValues(alpha: 0.2)
                          : AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (!isMe)
                          Text(
                            msg.username,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        Text(
                          msg.message,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat.Hm().format(msg.createdAt.toLocal()),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _historyAlbumPlaceholder() {
    return Container(
      width: 160,
      height: 160,
      color: AppTheme.surfaceColor,
      child: const Icon(Icons.album, size: 64, color: AppTheme.primaryColor),
    );
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
