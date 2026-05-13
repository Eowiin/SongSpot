import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/stats_provider.dart';
import '../game/category_select_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StatsProvider>().loadStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final stats = context.watch<StatsProvider>();
    final username = auth.user?.username ?? '';

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              _buildHeader(context, username),
              const SizedBox(height: 32),
              _buildStatsBanner(context, stats),
              const SizedBox(height: 40),
              Text(
                'Play',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 16),
              _buildModeCard(
                context,
                icon: Icons.music_note_rounded,
                label: 'Solo',
                sublabel: 'Guess as many songs as you want',
                gradient: AppTheme.primaryGradient,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CategorySelectScreen()),
                ),
              ),
              const SizedBox(height: 16),
              _buildModeCard(
                context,
                icon: Icons.people_rounded,
                label: '1v1',
                sublabel: 'Coming soon',
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF3A3A5C), Color(0xFF2A2A4A)],
                ),
                onTap: null,
                disabled: true,
              ),
              const Spacer(),
              _buildDeezerAttribution(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String username) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hi, $username',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Guess as many songs as you want',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.settings_rounded, color: AppTheme.textSecondary),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsBanner(BuildContext context, StatsProvider stats) {
    if (stats.isLoadingStats) return const SizedBox.shrink();
    final best = stats.userBest;
    if (best.totalSongsPlayed == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat('Best score', best.bestScoreOverall.toString()),
          _buildStatDivider(),
          _buildStat('Best streak', '${best.bestStreakOverall} 🔥'),
          _buildStatDivider(),
          _buildStat('Songs', best.totalSongsPlayed.toString()),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildStatDivider() {
    return Container(width: 1, height: 32, color: Colors.white.withOpacity(0.12));
  }

  Widget _buildModeCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String sublabel,
    required LinearGradient gradient,
    required VoidCallback? onTap,
    bool disabled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 110,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: disabled
              ? null
              : [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(disabled ? 0.08 : 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: disabled ? AppTheme.textSecondary : Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: disabled ? AppTheme.textSecondary : Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sublabel,
                      style: TextStyle(
                        color: disabled
                            ? AppTheme.textSecondary
                            : Colors.white.withOpacity(0.7),
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (!disabled)
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeezerAttribution() {
    return Center(
      child: Text(
        'Music previews powered by Deezer',
        style: TextStyle(
          color: AppTheme.textSecondary.withOpacity(0.5),
          fontSize: 11,
        ),
      ),
    );
  }
}
