import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/track.dart';
import '../../models/pack_bundle.dart';
import '../../providers/pack_bundle_provider.dart';
import '../../services/stem_audio_service.dart';
import '../../widgets/track_autocomplete.dart';

class PackBundleScreen extends StatefulWidget {
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
  State<PackBundleScreen> createState() => _PackBundleScreenState();
}

class _PackBundleScreenState extends State<PackBundleScreen> {
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

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.packName),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: provider.isLoading && session == null
            ? const Center(child: CircularProgressIndicator())
            : session == null
                ? Center(
                    child: Text(
                      provider.errorMessage ?? 'Pack session unavailable',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  )
                : session.isCompleted
                    ? _buildCompletedView(session.pointsEarned)
                    : SingleChildScrollView(
                        padding: AppTheme.pagePadding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildProgressCard(session),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _playStems,
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Play Stems'),
                            ),
                            const SizedBox(height: 16),
                            TrackAutocomplete(
                              controller: _titleController,
                              onTrackSelected: (track) {
                                _selectedTrack = track;
                              },
                              hintText: 'Search song title or artist',
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _skipStage,
                                    child: const Text('Skip Instrument'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _submitGuess,
                                    child: const Text('Submit Guess'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
      ),
    );
  }

  Widget _buildProgressCard(PackBundleSession session) {
    final stageNames = ['Drums', 'Bass', 'Other', 'Vocals'];
    final stageIndex = (session.currentStage as int) - 1;
    final stageLabel = stageIndex >= 0 && stageIndex < stageNames.length
        ? stageNames[stageIndex]
        : 'Stage ${session.currentStage}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily pack track',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '${session.date} • Stage ${session.currentStage} • $stageLabel',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Points: ${session.pointsEarned}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedView(int points) {
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
            'Total points: $points',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
