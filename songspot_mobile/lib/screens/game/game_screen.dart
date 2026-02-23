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
  Track? _selectedTrack;
  String? _activePackId;
  String? _activePackName;
  late GameProvider _gameProvider;

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
    });
  }

  @override
  void dispose() {
    _gameProvider.disconnectFromChat();
    _titleController.dispose();
    _messageController.dispose();
    _chatScrollController.dispose();
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

    final isCorrect = await gameProvider.submitGuess(
      roomId: widget.roomId,
      trackId: _selectedTrack!.id,
    );

    if (mounted) {
      _titleController.clear();
      _selectedTrack = null;
      if (isCorrect || gameProvider.currentSession!.isCompleted) {
        _onGameCompleted();
      }
    }
  }

  void _onGameCompleted() {
    // Refresh leaderboard and load messages when game is completed
    final gameProvider = context.read<GameProvider>();
    gameProvider.loadLeaderboard(widget.roomId);
    gameProvider.loadMessages(widget.roomId);
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
                      });
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
            onPressed: () => Navigator.pop(dialogContext, nameController.text.trim()),
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

  Widget _buildResultContent(GameSession session, List<LeaderboardEntry> leaderboard) {
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                      color: isCorrect ? AppTheme.successColor : AppTheme.errorColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isCorrect
                          ? '+${session.pointsEarned} points (Snippet ${session.currentSnippet})'
                          : 'Not guessed',
                      style: TextStyle(
                        color: isCorrect ? AppTheme.successColor : AppTheme.errorColor,
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
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ),

                  // Points
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
        Text(
          'Chat',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
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
                            gradient: isCurrentUser ? AppTheme.primaryGradient : null,
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
                                  color: isCurrentUser ? Colors.white70 : AppTheme.primaryColor,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                message.message,
                                style: TextStyle(
                                  color: isCurrentUser ? Colors.white : AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat.Hm().format(message.createdAt.toLocal()),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isCurrentUser ? Colors.white70 : AppTheme.textSecondary,
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
    final isHost = room != null && currentUserId != null && room.isHost(currentUserId);
    final packProvider = context.watch<PackProvider>();

    return Scaffold(
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
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: Consumer<GameProvider>(
          builder: (context, gameProvider, _) {
            // Show skeleton while loading or until session is available
            if (gameProvider.isLoading || gameProvider.currentSession == null) {
              return _buildLoadingSkeleton();
            }

            final session = gameProvider.currentSession;
            if (session == null) {
              return _buildLoadingSkeleton();
            }

            if (session.isCompleted) {
              return SingleChildScrollView(
                padding: AppTheme.pagePadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                  _buildPackSwitcher(context, packProvider.ownedPacks),
                  if (_activePackId == null)
                    ...[
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
                                color: isActive ? AppTheme.primaryColor : AppTheme.textSecondary,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '$snippetNumber',
                                style: TextStyle(
                                  color: isPassed || isActive ? Colors.white : AppTheme.textSecondary,
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
                              text: gameProvider.audioService.isPlaying ? '🔊 Playing...' : 'Play Snippet',
                              onPressed: gameProvider.audioService.isPlaying ? null : _handlePlaySnippet,
                              isLoading: false,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

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
                              onPressed: session.currentSnippet >= 6 ? null : _handleSkip,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.textPrimary,
                                side: const BorderSide(color: AppTheme.textSecondary),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppTheme.borderRadius),
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
                              onPressed: _handleGuess,
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
                    ]
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
          },
        ),
      ),
    );
  }
}
