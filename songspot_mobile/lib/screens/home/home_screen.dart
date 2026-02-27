import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/room.dart';
import '../../providers/auth_provider.dart';
import '../../providers/room_provider.dart';
import '../../widgets/gradient_button.dart';
import '../game/game_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _roomCodeController = TextEditingController();
  final Map<String, Room> _pendingDeletedRooms = {};
  final Map<String, Timer> _pendingDeleteTimers = {};
  final Set<String> _committingRoomIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RoomProvider>().loadMyRooms();
    });
  }

  @override
  void dispose() {
    for (final timer in _pendingDeleteTimers.values) {
      timer.cancel();
    }
    _pendingDeleteTimers.clear();
    _roomCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateRoom() async {
    final roomProvider = context.read<RoomProvider>();
    final room = await roomProvider.createRoom();

    if (room != null && mounted) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => GameScreen(roomId: room.id)));
      // Refresh rooms when returning from GameScreen
      if (mounted) {
        roomProvider.loadMyRooms();
      }
    } else if (mounted && roomProvider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(roomProvider.errorMessage!),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _handleJoinRoom() async {
    final l10n = AppLocalizations.of(context);
    final roomCode = _roomCodeController.text.trim().toUpperCase();
    if (roomCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseEnterRoomCode),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    final roomProvider = context.read<RoomProvider>();
    final room = await roomProvider.joinRoom(roomCode);

    if (room != null && mounted) {
      _roomCodeController.clear();
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => GameScreen(roomId: room.id)));
      // Refresh rooms when returning from GameScreen
      if (mounted) {
        roomProvider.loadMyRooms();
      }
    } else if (mounted && roomProvider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(roomProvider.errorMessage!),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  void _handleOpenSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  Future<bool> _handleRoomDismiss(Room room) async {
    final l10n = AppLocalizations.of(context);
    final roomId = room.id;
    if (_pendingDeletedRooms.containsKey(roomId) ||
        _committingRoomIds.contains(roomId)) {
      return false;
    }

    setState(() {
      _pendingDeletedRooms[roomId] = room;
    });
    _pendingDeleteTimers[roomId]?.cancel();
    _pendingDeleteTimers[roomId] = Timer(const Duration(seconds: 5), () {
      unawaited(_commitPendingRoomDeletion(roomId));
    });

    final currentUserId = context.read<AuthProvider>().user?.id;
    final isHost = currentUserId != null && room.isHost(currentUserId);
    final message = isHost && room.userCount > 1
        ? l10n.leftRoomHostTransferred
        : l10n.roomRemoved;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    unawaited(
      messenger
          .showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
              backgroundColor: AppTheme.surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: AppTheme.primaryColor.withValues(alpha: 0.45),
                ),
              ),
              content: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              action: SnackBarAction(
                label: l10n.undoAction,
                textColor: AppTheme.accentColor,
                onPressed: () => _undoPendingRoomDeletion(roomId),
              ),
            ),
          )
          .closed,
    );

    return true;
  }

  void _undoPendingRoomDeletion(String roomId) {
    if (!_pendingDeletedRooms.containsKey(roomId)) return;
    if (_committingRoomIds.contains(roomId)) return;

    _pendingDeleteTimers.remove(roomId)?.cancel();
    setState(() {
      _pendingDeletedRooms.remove(roomId);
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.surfaceColor,
          content: Text(
            AppLocalizations.of(context).roomDeletionCancelled,
            style: const TextStyle(color: AppTheme.textPrimary),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _commitPendingRoomDeletion(String roomId) async {
    if (!_pendingDeletedRooms.containsKey(roomId)) return;
    if (_committingRoomIds.contains(roomId)) return;

    _pendingDeleteTimers.remove(roomId)?.cancel();
    setState(() {
      _committingRoomIds.add(roomId);
    });

    final roomProvider = context.read<RoomProvider>();
    final success = await roomProvider.leaveRoomSilently(roomId);

    if (!mounted) return;

    setState(() {
      _committingRoomIds.remove(roomId);
      _pendingDeletedRooms.remove(roomId);
    });

    if (!success) {
      final errorText =
          roomProvider.errorMessage ??
          AppLocalizations.of(context).couldNotDeleteRoom;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorText.replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      roomProvider.clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final l10n = AppLocalizations.of(context);
    final horizontalPadding = MediaQuery.of(context).size.width < 360
        ? 16.0
        : 24.0;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppTheme.primaryColor,
                      child: Text(
                        user?.username[0].toUpperCase() ??
                            l10n.userFallback[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.username ?? l10n.userFallback,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            user?.email ?? '',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _StatChip(
                                label: '🔥 ${user?.currentStreak ?? 0}',
                                tooltip: l10n.dailyStreakTooltip,
                              ),
                              const SizedBox(width: 8),
                              _StatChip(
                                label: '🪙 ${user?.coins ?? 0}',
                                tooltip: l10n.coinsTooltip,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Semantics(
                      label: l10n.settingsTitle,
                      button: true,
                      child: IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: _handleOpenSettings,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Title
                      const Icon(
                        Icons.music_note,
                        size: 60,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.appTitle,
                        style: Theme.of(context).textTheme.displayMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),

                      // Create Room Button
                      GradientButton(
                        text: l10n.createRoom,
                        onPressed: _handleCreateRoom,
                        isLoading: context.watch<RoomProvider>().isLoading,
                      ),
                      const SizedBox(height: 24),

                      // Join Room Section
                      Text(
                        l10n.joinRoom,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _roomCodeController,
                              decoration: InputDecoration(
                                hintText: l10n.enterRoomCode,
                                filled: true,
                                fillColor: AppTheme.surfaceColor,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.borderRadius,
                                  ),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                              ),
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: [UpperCaseTextFormatter()],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            height: 56,
                            width: 56,
                            decoration: BoxDecoration(
                              gradient: AppTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(
                                AppTheme.borderRadius,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _handleJoinRoom,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.borderRadius,
                                ),
                                child: const Icon(
                                  Icons.arrow_forward,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),

                      // My Rooms Section
                      Text(
                        l10n.myRooms,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      Consumer<RoomProvider>(
                        builder: (context, roomProvider, _) {
                          if (roomProvider.isLoading) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          final visibleRooms = roomProvider.myRooms
                              .where(
                                (room) =>
                                    !_pendingDeletedRooms.containsKey(room.id),
                              )
                              .toList();

                          if (visibleRooms.isEmpty) {
                            return Container(
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                gradient: AppTheme.cardGradient,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.cardBorderRadius,
                                ),
                              ),
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.music_off,
                                    size: 48,
                                    color: AppTheme.textSecondary,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    l10n.noRoomsYet,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    l10n.noRoomsHint,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            );
                          }

                          return Column(
                            children: visibleRooms.map((room) {
                              return Dismissible(
                                key: ValueKey('room-${room.id}'),
                                direction: DismissDirection.endToStart,
                                dismissThresholds: const {
                                  DismissDirection.endToStart: 0.25,
                                },
                                background: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.errorColor.withValues(
                                      alpha: 0.85,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      AppTheme.cardBorderRadius,
                                    ),
                                  ),
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.delete_outline,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        l10n.deleteLabel,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                confirmDismiss: (_) => _handleRoomDismiss(room),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    gradient: AppTheme.cardGradient,
                                    borderRadius: BorderRadius.circular(
                                      AppTheme.cardBorderRadius,
                                    ),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                GameScreen(roomId: room.id),
                                          ),
                                        );
                                        // Refresh rooms when returning from GameScreen
                                        if (context.mounted) {
                                          context
                                              .read<RoomProvider>()
                                              .loadMyRooms();
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(
                                        AppTheme.cardBorderRadius,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryColor
                                                    .withValues(alpha: 0.2),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: const Icon(
                                                Icons.people,
                                                color: AppTheme.primaryColor,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    room.displayName,
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.titleLarge,
                                                  ),
                                                  Text(
                                                    '${l10n.members(room.userCount)} • ${room.roomCode}',
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.bodyMedium,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Icon(
                                              Icons.arrow_forward_ios,
                                              size: 16,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
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

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String tooltip;

  const _StatChip({required this.label, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
