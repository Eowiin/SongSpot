import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/room.dart';
import '../../providers/auth_provider.dart';
import '../../providers/room_provider.dart';
import '../../widgets/gradient_button.dart';
import '../game/game_screen.dart';

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
  @override
  void initState() {
    super.initState();
    // Schedule the refresh after the build is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshRoom();
    });
  }

  Future<void> _refreshRoom() async {
    await context.read<RoomProvider>().loadRoomDetails(widget.room.id);
  }

  Future<void> _showRenameDialog() async {
    final roomProvider = context.read<RoomProvider>();
    final room = roomProvider.currentRoom ?? widget.room;
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
    Clipboard.setData(ClipboardData(text: widget.room.roomCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Room code copied to clipboard!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roomProvider = context.watch<RoomProvider>();
    final room = roomProvider.currentRoom ?? widget.room;
    final currentUserId = context.watch<AuthProvider>().user?.id;
    final isHost = currentUserId != null && room.isHost(currentUserId);

    return Scaffold(
      appBar: AppBar(title: Text(room.displayName)),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: roomProvider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: AppTheme.pagePadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Room Code Card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: AppTheme.cardGradient,
                        borderRadius: BorderRadius.circular(
                          AppTheme.cardBorderRadius,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            room.displayName,
                            style: Theme.of(context).textTheme.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                          if (isHost) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _showRenameDialog,
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('Edit room name'),
                            ),
                          ],
                          const SizedBox(height: 8),
                          const Icon(
                            Icons.qr_code,
                            size: 60,
                            color: AppTheme.primaryColor,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Room Code',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                room.roomCode,
                                style: Theme.of(context).textTheme.displayLarge
                                    ?.copyWith(
                                      letterSpacing: 4,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: const Icon(Icons.copy),
                                onPressed: _copyRoomCode,
                                color: AppTheme.primaryColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Share this code with friends to join',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Play Button
                    if (widget.showPlayButton) ...[
                      GradientButton(
                        text: 'Play Today\'s Song',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => GameScreen(roomId: room.id),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 32),
                    ],

                    // Members Section
                    Text(
                      'Members (${room.userCount})',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    ...room.users.map((roomUser) {
                      final isHost = room.hostUser.id == roomUser.user.id;
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
                                  Row(
                                    children: [
                                      Text(
                                        roomUser.user.username,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      if (isHost) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryColor,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Text(
                                            'HOST',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
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
                    const SizedBox(height: 24),

                    // Leave Room Button
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
    );
  }
}
