import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../config/daily_mode_localization.dart';
import '../../l10n/app_localizations.dart';
import '../../models/pack.dart';
import '../../models/room.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pack_provider.dart';
import '../../providers/room_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/daily_mode_card.dart';
import '../../widgets/gradient_button.dart';
import '../game/game_screen.dart';
import '../packs/pack_list_screen.dart';

class RoomDetailScreen extends StatefulWidget {
  final Room room;
  final bool showPlayButton;

  const RoomDetailScreen({
    super.key,
    required this.room,
    this.showPlayButton = true,
  });

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  final ApiService _apiService = ApiService();
  bool _isInitialLoading = true;
  bool _isRefreshing = false;
  List<SongPack> _ownedPacks = const [];
  String? _packsErrorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshRoom(loadAsInitial: true);
    });
  }

  Future<void> _refreshRoom({bool loadAsInitial = false}) async {
    if (loadAsInitial) {
      setState(() {
        _isInitialLoading = true;
      });
    } else {
      setState(() {
        _isRefreshing = true;
      });
    }

    final roomProvider = context.read<RoomProvider>();

    try {
      await Future.wait([
        roomProvider.loadRoomDetails(widget.room.id),
        _loadOwnedPacks(),
      ]);
    } finally {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _loadOwnedPacks() async {
    try {
      final response = await _apiService.getMyPacks(roomId: widget.room.id);
      if (!mounted) return;
      setState(() {
        _ownedPacks = response
            .map((item) => SongPack.fromJson(item as Map<String, dynamic>))
            .toList();
        _packsErrorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _packsErrorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _showRenameDialog() async {
    final roomProvider = context.read<RoomProvider>();
    final room = _room;
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

    if (newName == null || !mounted) return;

    final result = await roomProvider.renameRoom(
      widget.room.id,
      newName.isEmpty ? null : newName,
    );

    if (!mounted) return;
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Room renamed successfully'),
          backgroundColor: AppTheme.successColor,
        ),
      );
      await _refreshRoom();
    } else if (roomProvider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(roomProvider.errorMessage!),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _handleLeaveRoom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Leave Room'),
        content: const Text('Are you sure you want to leave this room?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Leave',
              style: TextStyle(color: AppTheme.errorColor),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await context.read<RoomProvider>().leaveRoom(
        widget.room.id,
      );
      if (success && mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _copyRoomCode() {
    Clipboard.setData(ClipboardData(text: _room.roomCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Room code copied to clipboard!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openPackList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PackListScreen(roomId: widget.room.id)),
    );
    if (!mounted) return;
    await _refreshRoom();
  }

  Future<void> _showDailyModeContributionDialog(RoomDailyMode mode) async {
    final l10n = AppLocalizations.of(context);
    final auth = context.read<AuthProvider>().user;
    final accent = _dailyModeAccent(mode.mode);
    final maxAmount = math.min(mode.remainingCoins, auth?.coins ?? 0);
    final quickPicks = _suggestedContributionQuickPicks(
      remainingCoins: mode.remainingCoins,
      availableCoins: auth?.coins ?? 0,
    );
    final suggestedAmount = quickPicks.isNotEmpty
        ? quickPicks.first.amount
        : maxAmount;
    final controller = TextEditingController(
      text: suggestedAmount > 0 ? '$suggestedAmount' : '',
    );
    var selectedAmount = suggestedAmount;

    final amount = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppTheme.surfaceColor,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final progressMax = mode.costCoins <= 0 ? 1 : mode.costCoins;
          final progressValue = mode.progressCoins
              .clamp(0, progressMax)
              .toDouble();

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                20 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            _dailyModeIcon(mode.mode),
                            color: accent,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.dailyModeContributeTitle(
                                  dailyModeLocalizedLabel(l10n, mode.mode),
                                ),
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                dailyModeLocalizedSubtitle(l10n, mode.mode),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          tooltip: l10n.commonClose,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _ContributionStatCard(
                            label: l10n.dailyModeContributionRemainingLabel,
                            value: mode.remainingCoins > 0
                                ? l10n.dailyModeCoinsCost(mode.remainingCoins)
                                : l10n.dailyModeFunded,
                            accent: accent,
                            icon: Icons.monetization_on_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ContributionStatCard(
                            label: l10n.dailyModeContributionBalanceLabel,
                            value: l10n.dailyModeCoinsCost(auth?.coins ?? 0),
                            accent: AppTheme.primaryColor,
                            icon: Icons.account_balance_wallet_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 10,
                        value: progressValue / progressMax,
                        color: accent,
                        backgroundColor: AppTheme.backgroundColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          '${mode.progressCoins}/${mode.costCoins}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const Spacer(),
                        _ContributionMetricPill(
                          icon: Icons.groups_2_outlined,
                          label: '${mode.contributorCount}',
                        ),
                        const SizedBox(width: 8),
                        _ContributionMetricPill(
                          icon: mode.isUnlocked
                              ? Icons.check_circle_outline
                              : Icons.monetization_on_outlined,
                          label: mode.isUnlocked
                              ? l10n.dailyModeUnlocked
                              : l10n.dailyModeContributionLeft(
                                  mode.remainingCoins,
                                ),
                        ),
                      ],
                    ),
                    if (mode.isUnlocked) ...[
                      const SizedBox(height: 6),
                      Text(
                        l10n.dailyModeUnlockedUntilReset,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (!mode.isUnlocked) ...[
                      const SizedBox(height: 6),
                      Text(
                        l10n.dailyModeContributionProgress(
                          mode.progressCoins,
                          mode.costCoins,
                          mode.contributorCount,
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (quickPicks.isNotEmpty) ...[
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
                              setSheetState(() {
                                selectedAmount = pick.amount;
                                controller.text = '${pick.amount}';
                                controller.selection = TextSelection.collapsed(
                                  offset: controller.text.length,
                                );
                              });
                            },
                            selectedColor: accent.withValues(alpha: 0.24),
                            side: BorderSide(
                              color: selected
                                  ? accent.withValues(alpha: 0.6)
                                  : AppTheme.textSecondary.withValues(
                                      alpha: 0.18,
                                    ),
                            ),
                            avatar: Icon(
                              pick.isFill
                                  ? Icons.auto_fix_high_rounded
                                  : Icons.add_rounded,
                              size: 18,
                              color: selected ? accent : AppTheme.textSecondary,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text(
                      l10n.dailyModeCoinsRemainingYouHave(
                        mode.remainingCoins,
                        auth?.coins ?? 0,
                      ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: false,
                        signed: false,
                      ),
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (value) {
                        setSheetState(() {
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
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: selectedAmount > 0
                          ? () => Navigator.pop(sheetContext, selectedAmount)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        disabledBackgroundColor: AppTheme.surfaceColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        selectedAmount > 0
                            ? '${l10n.dailyModeContribute} • ${l10n.dailyModeCoinsCost(selectedAmount)}'
                            : l10n.dailyModeContribute,
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

    if (amount == null || amount <= 0 || !mounted) return;
    final response = await context.read<RoomProvider>().contributeToDailyMode(
      roomId: widget.room.id,
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

    if (response['is_unlocked'] as bool? ?? false) {
      await _showDailyModeUnlockedDialog(mode);
    }
  }

  List<_ContributionQuickPick> _suggestedContributionQuickPicks({
    required int remainingCoins,
    required int availableCoins,
  }) {
    final maxAmount = math.min(remainingCoins, availableCoins);
    if (maxAmount <= 0) return const [];

    final suggestions = <_ContributionQuickPick>[];
    for (final candidate in [10, 20]) {
      if (candidate <= 0 || candidate >= maxAmount) continue;
      suggestions.add(_ContributionQuickPick(amount: candidate));
    }
    suggestions.add(_ContributionQuickPick(amount: maxAmount, isFill: true));
    return suggestions;
  }

  Future<void> _showDailyModeUnlockedDialog(RoomDailyMode mode) async {
    if (!mounted) return;

    final l10n = AppLocalizations.of(context);
    final accent = _dailyModeAccent(mode.mode);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent.withValues(alpha: 0.24), AppTheme.surfaceColor],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accent.withValues(alpha: 0.34)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.auto_awesome, color: accent, size: 34),
              ),
              const SizedBox(height: 18),
              Text(
                dailyModeLocalizedLabel(l10n, mode.mode),
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.dailyModeUnlockedForRoom(
                  dailyModeLocalizedLabel(l10n, mode.mode),
                ),
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(l10n.commonClose),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _dailyModeIcon(String mode) {
    switch (mode) {
      case 'genre':
        return Icons.graphic_eq;
      case 'decade':
        return Icons.history_edu;
      case 'hardcore':
        return Icons.whatshot;
      default:
        return Icons.shuffle;
    }
  }

  Color _dailyModeAccent(String mode) {
    switch (mode) {
      case 'genre':
        return AppTheme.accentColor;
      case 'decade':
        return AppTheme.secondaryColor;
      case 'hardcore':
        return AppTheme.errorColor;
      default:
        return AppTheme.primaryColor;
    }
  }

  String _packPrimaryLabel(SongPack pack) {
    if (pack.isActive) return 'Activated';
    if (pack.isCompleted) return 'Used';
    if (pack.canActivate) return 'Activate';
    return 'Purchased';
  }

  bool _isPackActionEnabled(SongPack pack) {
    if (pack.isActive) return false;
    if (pack.isCompleted) return false;
    return pack.canActivate;
  }

  String _packStatusCopy(SongPack pack) {
    final activePack = _room.activePack;
    if (pack.isActive) {
      final currentDay = pack.currentDay;
      final totalDays = pack.totalDays;
      if (currentDay != null && totalDays > 0) {
        return 'Activated • Day $currentDay of $totalDays';
      }
      return 'Activated';
    }
    if (pack.isCompleted) {
      return 'Used in this room';
    }
    if (pack.canActivate) {
      return 'Can activate now';
    }
    if (activePack != null && activePack.id != pack.id) {
      return 'Available after active pack';
    }
    return 'Purchased for this room';
  }

  Color _packStatusColor(SongPack pack) {
    if (pack.isActive) return AppTheme.secondaryColor;
    if (pack.canActivate) return AppTheme.successColor;
    return AppTheme.textSecondary;
  }

  Future<void> _handlePackPrimaryAction(SongPack pack) async {
    if (!_isPackActionEnabled(pack)) return;

    final activateResponse = await context.read<PackProvider>().activatePack(
      roomId: widget.room.id,
      packId: pack.id,
    );
    if (!mounted) return;

    if (activateResponse != null) {
      final roomJson = activateResponse['room'] as Map<String, dynamic>?;
      if (roomJson != null) {
        context.read<RoomProvider>().setCurrentRoom(Room.fromJson(roomJson));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activateResponse['message'] as String? ??
                'Pack activated successfully',
          ),
          backgroundColor: AppTheme.successColor,
        ),
      );
      await _refreshRoom();
      return;
    }

    final errorMessage = context.read<PackProvider>().errorMessage;
    if (errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage.replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Room get _room {
    final providerRoom = context.read<RoomProvider>().currentRoom;
    if (providerRoom != null && providerRoom.id == widget.room.id) {
      return providerRoom;
    }
    return widget.room;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final providerRoom = context.watch<RoomProvider>().currentRoom;
    final room = providerRoom != null && providerRoom.id == widget.room.id
        ? providerRoom
        : widget.room;
    final currentUserId = context.watch<AuthProvider>().user?.id;
    final isHost = currentUserId != null && room.isHost(currentUserId);

    return Scaffold(
      appBar: AppBar(title: Text(room.displayName)),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: _isInitialLoading
            ? const _RoomDetailSkeleton()
            : RefreshIndicator(
                onRefresh: _refreshRoom,
                color: AppTheme.primaryColor,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: AppTheme.pagePadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isRefreshing)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: LinearProgressIndicator(
                            color: AppTheme.primaryColor,
                            backgroundColor: AppTheme.surfaceColor,
                          ),
                        ),
                      _buildOverviewCard(room: room, isHost: isHost),
                      if (widget.showPlayButton) ...[
                        const SizedBox(height: 20),
                        GradientButton(
                          text: 'Open Room',
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => GameScreen(roomId: room.id),
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 28),
                      _buildSectionHeader(
                        title: l10n.dailyModesTitle,
                        subtitle: l10n.dailyModesRoomIntro,
                      ),
                      const SizedBox(height: 12),
                      ...room.dailyModes.map(
                        (mode) => DailyModeCard(
                          mode: mode,
                          onContribute: mode.isFree
                              ? null
                              : () => _showDailyModeContributionDialog(mode),
                        ),
                      ),
                      const SizedBox(height: 28),
                      _buildSectionHeader(
                        title: 'Stem Packs',
                        subtitle:
                            'Owned by this room. Only one pack can be active at a time.',
                        action: TextButton(
                          onPressed: _openPackList,
                          child: const Text('Browse all'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_packsErrorMessage != null) ...[
                        _ErrorBanner(message: _packsErrorMessage!),
                        const SizedBox(height: 12),
                      ],
                      if (_ownedPacks.isEmpty)
                        _buildEmptyPacksState()
                      else
                        ..._ownedPacks.map(_buildPackCard),
                      const SizedBox(height: 28),
                      _buildSectionHeader(
                        title: 'Members (${room.userCount})',
                        subtitle: 'Everyone currently inside this room.',
                      ),
                      const SizedBox(height: 12),
                      ...room.users.map((roomUser) {
                        final memberIsHost =
                            room.hostUser.id == roomUser.user.id;
                        final isCurrentUser = currentUserId == roomUser.user.id;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: AppTheme.cardGradient,
                            borderRadius: BorderRadius.circular(
                              AppTheme.cardBorderRadius,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppTheme.primaryColor,
                                child: Text(
                                  roomUser.user.username[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          roomUser.user.username,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleLarge,
                                        ),
                                        if (memberIsHost)
                                          const _StatusTag(
                                            label: 'HOST',
                                            color: AppTheme.primaryColor,
                                          ),
                                        if (isCurrentUser)
                                          const _StatusTag(
                                            label: 'YOU',
                                            color: AppTheme.accentColor,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      roomUser.user.email,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _handleLeaveRoom,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.errorColor,
                          side: const BorderSide(color: AppTheme.errorColor),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.borderRadius,
                            ),
                          ),
                        ),
                        child: const Text('Leave Room'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildOverviewCard({required Room room, required bool isHost}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.groups_rounded,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.displayName,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Invite friends with the code below, then switch between the daily modes inside the room.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (isHost)
                IconButton(
                  onPressed: _showRenameDialog,
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Rename room',
                ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.backgroundColor.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Room code',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        room.roomCode,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              letterSpacing: 3,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _copyRoomCode,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusTag(
                label:
                    '${room.userCount} member${room.userCount == 1 ? '' : 's'}',
                color: AppTheme.primaryColor,
              ),
              _StatusTag(
                label:
                    '${_ownedPacks.length} pack${_ownedPacks.length == 1 ? '' : 's'}',
                color: AppTheme.secondaryColor,
              ),
              _StatusTag(
                label: 'Host: ${room.hostUser.username}',
                color: AppTheme.textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        if (action != null) action,
      ],
    );
  }

  Widget _buildEmptyPacksState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.library_music_outlined,
            size: 42,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            'No stem packs in this room yet',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Open the pack browser to unlock a room pack and it will show up here.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _openPackList,
            child: const Text('Browse stem packs'),
          ),
        ],
      ),
    );
  }

  Widget _buildPackCard(SongPack pack) {
    final isActionEnabled = _isPackActionEnabled(pack);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PackArtwork(iconUrl: pack.iconUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pack.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pack.category != null
                          ? '${pack.trackCount} tracks • ${pack.category}'
                          : '${pack.trackCount} tracks',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _packStatusCopy(pack),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _packStatusColor(pack),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 38,
                child: ElevatedButton(
                  onPressed: isActionEnabled
                      ? () => _handlePackPrimaryAction(pack)
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: Text(_packPrimaryLabel(pack)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomDetailSkeleton extends StatelessWidget {
  const _RoomDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: AppTheme.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SkeletonCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                _SkeletonLine(width: 180, height: 26),
                SizedBox(height: 10),
                _SkeletonLine(width: double.infinity, height: 14),
                SizedBox(height: 8),
                _SkeletonLine(width: 220, height: 14),
                SizedBox(height: 20),
                _SkeletonBlock(height: 88),
                SizedBox(height: 14),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SkeletonBlock(height: 52),
          const SizedBox(height: 28),
          const _SkeletonLine(width: 120, height: 22),
          const SizedBox(height: 6),
          const _SkeletonLine(width: 240, height: 14),
          const SizedBox(height: 12),
          const _SkeletonCard(child: _SkeletonBlock(height: 92)),
          const SizedBox(height: 12),
          const _SkeletonCard(child: _SkeletonBlock(height: 92)),
          const SizedBox(height: 28),
          const _SkeletonLine(width: 140, height: 22),
          const SizedBox(height: 6),
          const _SkeletonLine(width: 200, height: 14),
          const SizedBox(height: 12),
          const _SkeletonCard(child: _SkeletonBlock(height: 76)),
          const SizedBox(height: 12),
          const _SkeletonCard(child: _SkeletonBlock(height: 76)),
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final Widget child;

  const _SkeletonCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
      ),
      child: child,
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  final double width;
  final double height;

  const _SkeletonLine({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  final double height;

  const _SkeletonBlock({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.errorColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.borderRadius),
      ),
      child: Text(message, style: const TextStyle(color: AppTheme.errorColor)),
    );
  }
}

class _StatusTag extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
      ),
    );
  }
}

class _ContributionStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  final IconData icon;

  const _ContributionStatCard({
    required this.label,
    required this.value,
    required this.accent,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 18),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ContributionMetricPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ContributionMetricPill({required this.icon, required this.label});

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

class _ContributionQuickPick {
  final int amount;
  final bool isFill;

  const _ContributionQuickPick({required this.amount, this.isFill = false});
}

class _PackArtwork extends StatelessWidget {
  final String? iconUrl;

  const _PackArtwork({this.iconUrl});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.album_outlined, color: AppTheme.primaryColor),
    );

    if (iconUrl == null || iconUrl!.isEmpty) {
      return placeholder;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Image.network(
          iconUrl!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => placeholder,
        ),
      ),
    );
  }
}
