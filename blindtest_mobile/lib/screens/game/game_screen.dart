import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/app_theme.dart';
import '../../providers/game_provider.dart';
import '../../models/track.dart';
import '../../models/game_session.dart';
import '../../widgets/track_autocomplete.dart';
import '../../widgets/gradient_button.dart';
import 'chat_screen.dart';

class GameScreen extends StatefulWidget {
  final String roomId;

  const GameScreen({super.key, required this.roomId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final _titleController = TextEditingController();
  Track? _selectedTrack;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final gameProvider = context.read<GameProvider>();
      gameProvider.startGameSession(widget.roomId);
      gameProvider.loadLeaderboard(widget.roomId);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
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
    // Refresh leaderboard when game is completed
    context.read<GameProvider>().loadLeaderboard(widget.roomId);
  }

  Widget _buildResultView(GameSession session, List<LeaderboardEntry> leaderboard) {
    final track = session.dailySong.track;
    final isCorrect = session.correctGuess;

    return SingleChildScrollView(
      padding: AppTheme.pagePadding,
      child: Column(
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
          const SizedBox(height: 24),

          // Back Button
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textPrimary,
              side: const BorderSide(color: AppTheme.textSecondary),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.borderRadius),
              ),
            ),
            child: const Text('Back to Room'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Challenge'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(roomId: widget.roomId),
                ),
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: Consumer<GameProvider>(
          builder: (context, gameProvider, _) {
            if (gameProvider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            final session = gameProvider.currentSession;
            if (session == null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, size: 60, color: AppTheme.errorColor),
                    const SizedBox(height: 16),
                    Text(
                      gameProvider.errorMessage ?? 'Failed to load game',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            if (session.isCompleted) {
              return _buildResultView(session, gameProvider.leaderboard);
            }

            return SingleChildScrollView(
              padding: AppTheme.pagePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
