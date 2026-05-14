import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../main.dart' show routeObserver;
import '../../providers/auth_provider.dart';
import '../../providers/stats_provider.dart';
import '../auth/login_screen.dart';
import '../game/category_select_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final isGuest = context.read<AuthProvider>().isGuest;
      context.read<StatsProvider>().loadStats(isGuest: isGuest);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    final isGuest = context.read<AuthProvider>().isGuest;
    context.read<StatsProvider>().loadStats(isGuest: isGuest);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final stats = context.watch<StatsProvider>();
    final isGuest = auth.isGuest;
    final username = isGuest ? 'Guest' : (auth.user?.username ?? '');

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
                sublabel: isGuest ? 'Sign in to play' : 'Coming soon',
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF3A3A5C), Color(0xFF2A2A4A)],
                ),
                onTap: isGuest ? _showSignInPrompt : null,
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

  void _showSignInPrompt() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text(
          'Sign in required',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          '1v1 mode requires an account. Sign in or create one to play against others.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: Text(
              'Sign in',
              style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
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
    if (stats.isLoadingStats) return _buildStatsBannerSkeleton();
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

  Widget _buildStatsBannerSkeleton() {
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
          _buildSkeletonStat(),
          _buildStatDivider(),
          _buildSkeletonStat(),
          _buildStatDivider(),
          _buildSkeletonStat(),
        ],
      ),
    );
  }

  Widget _buildSkeletonStat() {
    return Column(
      children: [
        _SkeletonBox(width: 48, height: 20),
        const SizedBox(height: 6),
        _SkeletonBox(width: 36, height: 10),
      ],
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

class _SkeletonBox extends StatefulWidget {
  final double width;
  final double height;

  const _SkeletonBox({required this.width, required this.height});

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.25, end: 0.6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(_anim.value),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
