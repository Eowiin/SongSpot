import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/track.dart';
import '../../models/pack_bundle.dart';
import '../../providers/pack_bundle_provider.dart';
import '../../services/stem_audio_service.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/track_autocomplete.dart';

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
      appBar: AppBar(
        title: Text(packName),
      ),
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
  final StemAudioService _stemAudioService = StemAudioService();
  Track? _selectedTrack;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PackBundleProvider>().loadSession(
            roomId: widget.roomId,
            packId: widget.packId,
          );
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _stemAudioService.dispose();
    super.dispose();
  }

  Future<void> _playStems() async {
    final provider = context.read<PackBundleProvider>();
    final stems = provider.stems.map((stem) => stem.url).toList();
    if (stems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No stems available for this stage'),
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
          content: Text('Failed to play stems: $e'),
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
    if (_selectedTrack == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a song from the search results'),
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PackBundleProvider>();
    final session = provider.session;

    final content = provider.isLoading && session == null
        ? const Center(child: CircularProgressIndicator())
        : session == null
            ? Center(
                child: Text(
                  provider.errorMessage ?? 'Pack session unavailable',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              )
            : session.isCompleted
                ? _buildCompletedView(session)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStageIndicators(session),
                      const SizedBox(height: 32),
                      _buildProgressCard(session, onPlay: _playStems),
                      const SizedBox(height: 32),
                      Text(
                        'Make Your Guess',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      TrackAutocomplete(
                        controller: _titleController,
                        onTrackSelected: (track) {
                          _selectedTrack = track;
                        },
                        hintText: 'Search song title or artist',
                        labelText: 'Song Title',
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
                                  borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                                ),
                              ),
                              child: const Text('Skip Instrument'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GradientButton(
                              text: 'Submit Guess',
                              onPressed: _submitGuess,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );

    if (widget.embedInScroll) {
      return content;
    }

    return SingleChildScrollView(
      padding: AppTheme.pagePadding,
      child: content,
    );
  }

  Widget _buildProgressCard(PackBundleSession session, {required VoidCallback onPlay}) {
    final stageNames = ['Drums', 'Bass', 'Other', 'Vocals'];
    final stageIndex = (session.currentStage as int) - 1;
    final clampedIndex = stageIndex.clamp(0, stageNames.length - 1);
    final activeStages = stageNames.take(clampedIndex + 1).toList();
    final stageLabel = activeStages.isEmpty
        ? 'Stage ${session.currentStage}'
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
          const Icon(
            Icons.graphic_eq,
            size: 80,
            color: AppTheme.primaryColor,
          ),
          const SizedBox(height: 24),
          Text(
            'Stage ${session.currentStage}',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 8),
          Text(
            stageLabel,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppTheme.primaryColor,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '${session.pointsEarned} points so far',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          GradientButton(
            text: 'Play Stems',
            onPressed: onPlay,
            isLoading: false,
          ),
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
                color: isPassed || isActive ? Colors.white : AppTheme.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCompletedView(PackBundleSession session) {
    final track = session.packTrack?.track;
    if (track == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 60, color: AppTheme.successColor),
            const SizedBox(height: 16),
            Text(
              'Pack completed!',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Total points: ${session.pointsEarned}',
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                      'Pack completed · ${session.pointsEarned} points',
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
      ],
    );
  }
}
