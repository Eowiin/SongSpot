import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/category.dart';
import '../../models/track.dart';
import '../../providers/game_session_provider.dart';
import 'session_end_screen.dart';

class GameScreen extends StatefulWidget {
  final Category? category;
  final String? artistFilter;

  const GameScreen({super.key, this.category, this.artistFilter});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _guessController = TextEditingController();
  final FocusNode _guessFocus = FocusNode();
  late AnimationController _revealAnimController;
  late Animation<double> _revealAnim;

  @override
  void initState() {
    super.initState();
    _revealAnimController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _revealAnim = CurvedAnimation(parent: _revealAnimController, curve: Curves.easeOut);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<GameSessionProvider>();
      provider.startSession(
        category: widget.category,
        artistFilter: widget.artistFilter,
      );
      provider.loadNextSong();
    });
  }

  @override
  void dispose() {
    _guessController.dispose();
    _guessFocus.dispose();
    _revealAnimController.dispose();
    super.dispose();
  }

  Future<void> _nextSong() async {
    _revealAnimController.reset();
    _guessController.clear();
    _guessFocus.unfocus();
    await context.read<GameSessionProvider>().loadNextSong();
  }

  Future<void> _endSession() async {
    _guessFocus.unfocus();
    final provider = context.read<GameSessionProvider>();
    final score = await provider.endSession();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SessionEndScreen(
          score: score,
          songsPlayed: provider.songsPlayed,
          songsCorrect: provider.songsCorrect,
          bestStreak: provider.bestStreak,
          totalScore: provider.totalScore,
          category: widget.category,
          artistFilter: widget.artistFilter,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameSessionProvider>(
      builder: (context, provider, _) {
        final wasRevealed = provider.revealAnswer;
        if (wasRevealed && _revealAnimController.status == AnimationStatus.dismissed) {
          _revealAnimController.forward();
        }

        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: _buildAppBar(provider),
          body: SafeArea(
            child: provider.isLoadingTrack && provider.currentTrack == null
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                : provider.trackError != null && provider.currentTrack == null
                    ? _buildError(provider)
                    : _buildGameBody(context, provider),
          ),
        );
      },
    );
  }

  AppBar _buildAppBar(GameSessionProvider provider) {
    return AppBar(
      backgroundColor: AppTheme.backgroundColor,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: AppTheme.surfaceColor,
              title: const Text('End session?',
                  style: TextStyle(color: AppTheme.textPrimary)),
              content: const Text('Your progress will be submitted.',
                  style: TextStyle(color: AppTheme.textSecondary)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('End',
                      style: TextStyle(color: AppTheme.primaryColor)),
                ),
              ],
            ),
          );
          if (confirmed == true) _endSession();
        },
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded,
              color: Color(0xFFFF6B35), size: 20),
          const SizedBox(width: 4),
          Text(
            '${provider.currentStreak}',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(width: 16),
          const Icon(Icons.star_rounded, color: AppTheme.primaryColor, size: 18),
          const SizedBox(width: 4),
          Text(
            '${provider.totalScore}',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
      centerTitle: true,
    );
  }

  Widget _buildError(GameSessionProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(provider.trackError!,
              style: const TextStyle(color: AppTheme.textSecondary),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: provider.loadNextSong,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildGameBody(BuildContext context, GameSessionProvider provider) {
    final track = provider.currentTrack;
    final revealed = provider.revealAnswer;

    return Column(
      children: [
        // Scrollable top section — shrinks when keyboard opens
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              children: [
                _buildAlbumArt(provider, track),
                const SizedBox(height: 24),
                _buildPlaybackRow(provider),
                if (revealed) ...[
                  const SizedBox(height: 24),
                  _buildResultCard(provider, track),
                ],
              ],
            ),
          ),
        ),
        // Fixed bottom section — always visible above keyboard
        if (!revealed) ...[
          if (provider.searchResults.isNotEmpty)
            _buildAutocomplete(provider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _buildGuessInput(provider),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _buildGiveUpButton(provider),
          ),
        ],
        if (revealed) _buildBottomBar(provider),
      ],
    );
  }

  Widget _buildAlbumArt(GameSessionProvider provider, Track? track) {
    return AnimatedBuilder(
      animation: _revealAnim,
      builder: (context, child) {
        final blurSigma = (1 - _revealAnim.value) * 20.0;
        return Container(
          width: double.infinity,
          height: 240,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: AppTheme.surfaceColor,
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (track?.coverUrl != null)
                Image.network(
                  track!.coverUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const _PlaceholderArt(),
                )
              else
                const _PlaceholderArt(),
              if (blurSigma > 0.5)
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                  child: Container(color: Colors.black.withOpacity(0.2)),
                ),
              if (provider.isLoadingTrack)
                Container(
                  color: Colors.black.withOpacity(0.4),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlaybackRow(GameSessionProvider provider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: provider.isPlaying ? null : provider.replaySnippet,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            decoration: BoxDecoration(
              gradient: provider.isPlaying ? null : AppTheme.primaryGradient,
              color: provider.isPlaying ? AppTheme.surfaceColor : null,
              borderRadius: BorderRadius.circular(50),
              boxShadow: provider.isPlaying
                  ? null
                  : [
                      BoxShadow(
                        color: AppTheme.primaryColor.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  provider.isPlaying
                      ? Icons.volume_up_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  provider.isPlaying ? 'Playing...' : 'Play',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGuessInput(GameSessionProvider provider) {
    return TextField(
      controller: _guessController,
      focusNode: _guessFocus,
      style: const TextStyle(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        hintText: 'Type song title...',
        hintStyle: const TextStyle(color: AppTheme.textSecondary),
        prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
        suffixIcon: provider.isSearching
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.primaryColor),
                ),
              )
            : _guessController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, color: AppTheme.textSecondary),
                    onPressed: () {
                      _guessController.clear();
                      provider.clearSearch();
                    },
                  )
                : null,
        filled: true,
        fillColor: AppTheme.surfaceColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (q) => provider.searchTracks(q),
    );
  }

  Widget _buildAutocomplete(GameSessionProvider provider) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: provider.searchResults.length.clamp(0, 6),
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: Colors.white.withOpacity(0.06)),
        itemBuilder: (context, i) {
          final t = provider.searchResults[i];
          return ListTile(
            dense: true,
            leading: t.coverUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(t.coverUrl!,
                        width: 40, height: 40, fit: BoxFit.cover),
                  )
                : Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.music_note_rounded,
                        color: AppTheme.primaryColor, size: 20),
                  ),
            title: Text(t.title,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            subtitle: Text(t.artist,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            onTap: () {
              _guessFocus.unfocus();
              _guessController.clear();
              provider.submitGuess(t);
            },
          );
        },
      ),
    );
  }

  Widget _buildGiveUpButton(GameSessionProvider provider) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: provider.giveUp,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.textSecondary,
          side: BorderSide(color: AppTheme.textSecondary.withOpacity(0.3)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Text('Give up'),
      ),
    );
  }

  Widget _buildResultCard(GameSessionProvider provider, Track? track) {
    final isCorrect = provider.lastGuessResult == GuessResult.correct;
    final color = isCorrect ? const Color(0xFF4CAF50) : const Color(0xFFE53935);
    final icon = isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded;

    return AnimatedBuilder(
      animation: _revealAnim,
      builder: (context, _) {
        return Opacity(
          opacity: _revealAnim.value,
          child: Transform.translate(
            offset: Offset(0, (1 - _revealAnim.value) * 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: color, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        isCorrect ? 'Correct!' : 'Wrong',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (isCorrect) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '+${provider.totalScore > 0 ? (provider.songsCorrect > 0 ? 10 : 0) : 0} pts',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (track != null) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 12),
                    Text(
                      track.title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artist,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    if (track.releaseYear != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${track.releaseYear}',
                        style: TextStyle(
                          color: AppTheme.textSecondary.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(GameSessionProvider provider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: provider.isLoadingTrack ? null : _nextSong,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: provider.isLoadingTrack
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Next', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PlaceholderArt extends StatelessWidget {
  const _PlaceholderArt();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surfaceColor,
      child: const Icon(Icons.music_note_rounded,
          color: AppTheme.textSecondary, size: 64),
    );
  }
}
