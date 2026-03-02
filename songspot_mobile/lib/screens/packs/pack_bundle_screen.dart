import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/track.dart';
import '../../models/pack_bundle.dart';
import '../../providers/auth_provider.dart';
import '../../providers/game_provider.dart';
import '../../providers/pack_bundle_provider.dart';
import '../../services/stem_audio_service.dart';
import '../../services/websocket_service.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/track_autocomplete.dart';

// Hint order: sequential unlocking, same as daily game
const _packHintOrder = [
  {'type': 'genre', 'cost': 30},
  {'type': 'decade', 'cost': 60},
  {'type': 'artist_name', 'cost': 100},
];

class PackBundleScreen extends StatelessWidget {
  final String roomId;
  final String packId;
  final String packName;

  const PackBundleScreen({
    super.key,
    required this.roomId,
    required this.packId,
    required this.packName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(packName)),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: PackBundleContent(
          roomId: roomId,
          packId: packId,
          packName: packName,
        ),
      ),
    );
  }
}

class PackBundleContent extends StatefulWidget {
  final String roomId;
  final String packId;
  final String packName;
  final bool embedInScroll;

  const PackBundleContent({
    super.key,
    required this.roomId,
    required this.packId,
    required this.packName,
    this.embedInScroll = false,
  });

  @override
  State<PackBundleContent> createState() => _PackBundleContentState();
}

class _PackBundleContentState extends State<PackBundleContent> {
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _chatScrollController = ScrollController();
  final StemAudioService _stemAudioService = StemAudioService();
  Track? _selectedTrack;
  bool _requestedCompletionData = false;
  StreamSubscription<WebSocketEvent>? _wsSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      () async {
        final provider = context.read<PackBundleProvider>();

        // If this pack is already loaded in the provider, skip the reload to
        // avoid a flash of stale hint state. Just wire up the WebSocket.
        if (provider.loadedPackId == widget.packId &&
            provider.session != null) {
          _listenForStemsReady();
          return;
        }

        await provider.loadSession(
          roomId: widget.roomId,
          packId: widget.packId,
        );
        _listenForStemsReady();
        if (provider.session?.isCompleted == true) {
          await provider.loadLeaderboard(
            roomId: widget.roomId,
            packId: widget.packId,
          );
          await provider.loadMessages(
            roomId: widget.roomId,
            packId: widget.packId,
          );
          if (mounted) {
            setState(() {
              _requestedCompletionData = true;
            });
          }
        }
      }();
    });
  }

  void _listenForStemsReady() {
    _wsSubscription?.cancel();
    final gameProvider = context.read<GameProvider>();
    _wsSubscription = gameProvider.webSocketEvents.listen((event) {
      if (event.type == WebSocketEventType.stemsReady) {
        final data = event.data as Map<String, dynamic>?;
        final packId = data?['pack_id'] as String?;
        if (packId == widget.packId && mounted) {
          context.read<PackBundleProvider>().loadSession(
            roomId: widget.roomId,
            packId: widget.packId,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _titleController.dispose();
    _messageController.dispose();
    _chatScrollController.dispose();
    _stemAudioService.dispose();
    super.dispose();
  }

  Future<void> _playStems() async {
    final l10n = AppLocalizations.of(context);
    final provider = context.read<PackBundleProvider>();
    if (provider.stemsStatus == 'generating') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.packStemsGeneratingTryAgain),
          backgroundColor: AppTheme.primaryColor,
        ),
      );
      return;
    }
    final stems = provider.stems.map((stem) => stem.url).toList();
    if (stems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.packNoStemsAvailableForStage),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }
    try {
      await _stemAudioService.playStems(stems);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.packFailedToPlayStems(e.toString())),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _skipStage() async {
    await _stemAudioService.stop();
    await context.read<PackBundleProvider>().skipStage(
      roomId: widget.roomId,
      packId: widget.packId,
    );
  }

  Future<void> _submitGuess() async {
    final l10n = AppLocalizations.of(context);
    if (_selectedTrack == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.gameSelectSongFromResults),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }
    await _stemAudioService.stop();
    final provider = context.read<PackBundleProvider>();
    await provider.submitGuess(
      roomId: widget.roomId,
      packId: widget.packId,
      trackId: _selectedTrack!.id,
    );
    if (provider.guessResult != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.guessResult!),
          backgroundColor: AppTheme.primaryColor,
        ),
      );
      provider.clearGuessResult();
    }
  }

  Future<void> _handleSendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    final provider = context.read<PackBundleProvider>();
    final success = await provider.sendMessage(
      roomId: widget.roomId,
      packId: widget.packId,
      message: message,
    );

    if (success && mounted) {
      _messageController.clear();
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = context.watch<PackBundleProvider>();
    final session = provider.session;

    final content = provider.isLoading && session == null
        ? _buildLoadingSkeleton()
        : session == null
        ? _buildLoadingSkeleton()
        : session.isCompleted
        ? _buildCompletedView(session, provider)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStageIndicators(session),
              const SizedBox(height: 32),
              _buildProgressCard(session, onPlay: _playStems),
              const SizedBox(height: 24),
              _buildHintsSection(context, provider),
              const SizedBox(height: 24),
              Text(
                l10n.gameMakeYourGuess,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              TrackAutocomplete(
                controller: _titleController,
                onTrackSelected: (track) {
                  _selectedTrack = track;
                },
                hintText: l10n.packSearchSongTitleOrArtist,
                labelText: l10n.gameSongTitleLabel,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _skipStage,
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
                      child: Text(l10n.packSkipInstrument),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GradientButton(
                      text: l10n.gameSubmitGuess,
                      onPressed: _submitGuess,
                    ),
                  ),
                ],
              ),
            ],
          );

    if (session?.isCompleted == true && !_requestedCompletionData) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _requestedCompletionData) return;
        provider.loadLeaderboard(roomId: widget.roomId, packId: widget.packId);
        provider.loadMessages(roomId: widget.roomId, packId: widget.packId);
        setState(() {
          _requestedCompletionData = true;
        });
      });
    }

    if (widget.embedInScroll) {
      return content;
    }

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: AppTheme.pagePadding.copyWith(
        bottom: AppTheme.pagePadding.bottom + bottomInset,
      ),
      child: content,
    );
  }

  // ── Hints ───────────────────────────────────────────────────────────────

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

  Widget _buildHintsSection(BuildContext context, PackBundleProvider provider) {
    final l10n = AppLocalizations.of(context);
    final hintValues = provider.hintValues;
    final nextIndex = _packHintOrder.indexWhere(
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
          children: _packHintOrder.asMap().entries.map((entry) {
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
                  right: i == _packHintOrder.length - 1 ? 0 : 6,
                ),
                child: _buildHintButton(
                  context: context,
                  provider: provider,
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
    required PackBundleProvider provider,
    required String hintType,
    required String label,
    required int cost,
    required String? revealedValue,
    required String revealedLabel,
    required bool isLocked,
  }) {
    if (revealedValue != null) {
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

    return OutlinedButton(
      onPressed: () => _handlePurchaseHint(context, provider, hintType),
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
    PackBundleProvider provider,
    String hintType,
  ) async {
    try {
      final response = await provider.purchaseHint(
        roomId: widget.roomId,
        packId: widget.packId,
        hintType: hintType,
      );
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

  Widget _buildLoadingSkeleton() {
    return SingleChildScrollView(
      padding: AppTheme.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
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
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: AppTheme.cardGradient,
              borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
            ),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: 120,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 160,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 24),
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
              const SizedBox(width: 12),
              Expanded(
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

  Widget _buildProgressCard(
    PackBundleSession session, {
    required VoidCallback onPlay,
  }) {
    final l10n = AppLocalizations.of(context);
    final stemsStatus = context.watch<PackBundleProvider>().stemsStatus;
    final stageNames = [
      l10n.packStageDrums,
      l10n.packStageBass,
      l10n.packStageOther,
      l10n.packStageVocals,
    ];
    final stageIndex = session.currentStage - 1;
    final clampedIndex = stageIndex.clamp(0, stageNames.length - 1);
    final activeStages = stageNames.take(clampedIndex + 1).toList();
    final stageLabel = activeStages.isEmpty
        ? l10n.packStageLabel(session.currentStage)
        : activeStages.join(' + ');

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.graphic_eq, size: 80, color: AppTheme.primaryColor),
          const SizedBox(height: 24),
          Text(
            l10n.packStageLabel(session.currentStage),
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 8),
          Text(
            stageLabel,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: AppTheme.primaryColor),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.packPointsSoFar(session.pointsEarned),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (stemsStatus == 'generating') ...[
            const SizedBox(height: 16),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppTheme.primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.packPreparingChallenge,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: AppTheme.primaryColor),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.packPreparingChallengeSubtitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
            ),
          ] else ...[
            const SizedBox(height: 24),
            GradientButton(text: l10n.packPlayStems, onPressed: onPlay),
          ],
        ],
      ),
    );
  }

  Widget _buildStageIndicators(PackBundleSession session) {
    final totalStages = 4;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalStages, (index) {
        final stageNumber = index + 1;
        final isActive = stageNumber == session.currentStage;
        final isPassed = stageNumber < session.currentStage;

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
              color: isActive ? AppTheme.primaryColor : AppTheme.textSecondary,
              width: 2,
            ),
          ),
          child: Center(
            child: Text(
              '$stageNumber',
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
    );
  }

  Widget _buildCompletedView(
    PackBundleSession session,
    PackBundleProvider provider,
  ) {
    final l10n = AppLocalizations.of(context);
    final track = session.packTrack?.track;
    if (track == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle,
              size: 60,
              color: AppTheme.successColor,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.packCompleted,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.packTotalPoints(session.pointsEarned),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
              Container(
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
                    const Icon(
                      Icons.check_circle,
                      color: AppTheme.successColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.packCompletedSummary(session.pointsEarned),
                      style: const TextStyle(
                        color: AppTheme.successColor,
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
        _buildResultsSection(provider),
        const SizedBox(height: 32),
        _buildChatSection(provider),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildResultsSection(PackBundleProvider provider) {
    final l10n = AppLocalizations.of(context);
    final leaderboard = provider.leaderboard;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.packResultsTitle,
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
              l10n.packNoOtherPlayersCompleted,
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          leaderboardEntry.user.username,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          l10n.packStageCompletedAt(
                            leaderboardEntry.stageNumber,
                            DateFormat.Hm().format(
                              leaderboardEntry.completedAt.toLocal(),
                            ),
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
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
      ],
    );
  }

  Widget _buildChatSection(PackBundleProvider provider) {
    final l10n = AppLocalizations.of(context);
    final currentUserId = context.watch<AuthProvider>().user?.id;
    final messages = provider.messages;
    final displayMessages = messages.take(10).toList().reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.chatTitle, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
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
                        l10n.chatNoMessagesYet,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.chatStartConversation,
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
                              Text(
                                isCurrentUser
                                    ? l10n.chatYou
                                    : message.user.username,
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
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: l10n.chatTypeMessageHint,
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
}
