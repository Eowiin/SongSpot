import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../providers/game_provider.dart';
import '../../models/track.dart';
import '../../widgets/track_autocomplete.dart';
import '../../widgets/gradient_button.dart';
import 'leaderboard_screen.dart';
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
      context.read<GameProvider>().startGameSession(widget.roomId);
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
      if (isCorrect) {
        _titleController.clear();
        _selectedTrack = null;
        _showResultDialog(true);
      } else {
        _titleController.clear();
        _selectedTrack = null;
        if (gameProvider.currentSession!.isCompleted) {
          _showResultDialog(false);
        }
      }
    }
  }

  void _showResultDialog(bool isCorrect) {
    final gameProvider = context.read<GameProvider>();
    final session = gameProvider.currentSession!;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text(
          isCorrect ? '🎉 Correct!' : '😔 Game Over',
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCorrect) ...[
              Text(
                'You earned ${session.pointsEarned} points!',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Guessed on snippet ${session.currentSnippet}',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ] else ...[
              Text(
                'The song was:',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                session.dailySong.track.title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              Text(
                'by ${session.dailySong.track.artist}',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LeaderboardScreen(roomId: widget.roomId),
                ),
              );
            },
            child: const Text('View Leaderboard'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Close'),
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
            icon: const Icon(Icons.leaderboard),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LeaderboardScreen(roomId: widget.roomId),
                ),
              );
            },
          ),
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

            if (session.isCompleted && session.correctGuess) {
              return Center(
                child: SingleChildScrollView(
                  padding: AppTheme.pagePadding,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle, size: 100, color: AppTheme.successColor),
                      const SizedBox(height: 24),
                      Text(
                        'You already completed today\'s challenge!',
                        style: Theme.of(context).textTheme.displaySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'You earned ${session.pointsEarned} points',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      GradientButton(
                        text: 'View Leaderboard',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LeaderboardScreen(roomId: widget.roomId),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
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
