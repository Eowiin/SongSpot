import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/category.dart';
import '../../providers/auth_provider.dart';
import '../../providers/game_session_provider.dart';
import '../../services/api_service.dart';
import '../auth/login_screen.dart';
import 'game_screen.dart';

class ArtistInfo {
  final String name;
  final String? pictureUrl;

  const ArtistInfo({required this.name, this.pictureUrl});

  factory ArtistInfo.fromJson(Map<String, dynamic> j) => ArtistInfo(
        name: j['name'] as String,
        pictureUrl: j['picture_url'] as String?,
      );

  @override
  bool operator ==(Object other) => other is ArtistInfo && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

class CategorySelectScreen extends StatefulWidget {
  const CategorySelectScreen({super.key});

  @override
  State<CategorySelectScreen> createState() => _CategorySelectScreenState();
}

class _CategorySelectScreenState extends State<CategorySelectScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tabController;

  List<Category> _categories = [];
  bool _isLoading = true;
  String? _error;

  // Artist search
  final TextEditingController _artistController = TextEditingController();
  List<ArtistInfo> _artistResults = [];
  bool _isSearchingArtists = false;

  // Artist suggestions
  List<ArtistInfo> _trending = [];
  List<ArtistInfo> _favourites = [];
  bool _isLoadingArtistData = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCategories();
    _tabController.addListener(() {
      if (_tabController.index == 1 && _trending.isEmpty && _favourites.isEmpty) {
        _loadArtistData();
      }
    });
    _artistController.addListener(_onArtistQueryChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _artistController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final data = await _api.getCategories();
      setState(() {
        _categories = (data as List<dynamic>)
            .map((j) => Category.fromJson(j as Map<String, dynamic>))
            .where((c) => c.trackCount > 0)
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadArtistData() async {
    if (_isLoadingArtistData) return;
    setState(() => _isLoadingArtistData = true);
    try {
      final results = await Future.wait([
        _api.getTrendingArtists(),
        _api.getFavouriteArtists(),
      ]);
      if (mounted) {
        setState(() {
          _trending = results[0]
              .map((j) => ArtistInfo.fromJson(j as Map<String, dynamic>))
              .toList();
          _favourites = results[1]
              .map((j) => ArtistInfo.fromJson(j as Map<String, dynamic>))
              .toList();
          _isLoadingArtistData = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingArtistData = false);
    }
  }

  Future<void> _onArtistQueryChanged() async {
    final q = _artistController.text.trim();
    if (q.length < 2) {
      setState(() => _artistResults = []);
      return;
    }
    setState(() => _isSearchingArtists = true);
    try {
      final results = await _api.searchArtists(q);
      if (mounted) {
        setState(() {
          _artistResults = results
              .map((j) => ArtistInfo.fromJson(j as Map<String, dynamic>))
              .toList();
          _isSearchingArtists = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSearchingArtists = false);
    }
  }

  Future<void> _toggleFavourite(ArtistInfo artist) async {
    if (context.read<AuthProvider>().isGuest) {
      _showSignInPrompt();
      return;
    }
    final isFav = _favourites.contains(artist);
    setState(() {
      if (isFav) {
        _favourites.remove(artist);
      } else {
        _favourites.insert(0, artist);
      }
    });
    try {
      if (isFav) {
        await _api.removeFavouriteArtist(artist.name);
      } else {
        await _api.addFavouriteArtist(artist.name);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (isFav) {
            _favourites.insert(0, artist);
          } else {
            _favourites.remove(artist);
          }
        });
      }
    }
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
          'You need an account to save favourite artists.',
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

  Future<void> _startWithCategory(Category category) async {
    final difficulty = await _showPreGameModal(
      title: category.name,
      subtitle: '${category.trackCount} songs',
    );
    if (difficulty == null || !mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(category: category, difficulty: difficulty),
      ),
    );
  }

  Future<void> _startWithArtist(ArtistInfo artist) async {
    final difficulty = await _showPreGameModal(title: artist.name);
    if (difficulty == null || !mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(artistFilter: artist.name, difficulty: difficulty),
      ),
    );
  }

  Future<Difficulty?> _showPreGameModal({
    required String title,
    String? subtitle,
  }) async {
    Difficulty selected = Difficulty.medium;

    return showModalBottomSheet<Difficulty>(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Title
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 14)),
                ],
                const SizedBox(height: 24),
                const Text(
                  'DIFFICULTY',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                // Difficulty options
                ...Difficulty.values.map((d) {
                  final isSelected = selected == d;
                  final color = _difficultyColor(d);
                  return GestureDetector(
                    onTap: () => setModalState(() => selected = d),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? color.withOpacity(0.12)
                            : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? color.withOpacity(0.6)
                              : Colors.white.withOpacity(0.08),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            color: isSelected ? color : AppTheme.textSecondary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.label,
                                  style: TextStyle(
                                    color: isSelected
                                        ? AppTheme.textPrimary
                                        : AppTheme.textSecondary,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  _difficultyDescription(d),
                                  style: TextStyle(
                                    color: isSelected
                                        ? color
                                        : AppTheme.textSecondary
                                            .withOpacity(0.5),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _difficultyMultiplier(d),
                            style: TextStyle(
                              color: isSelected ? color : AppTheme.textSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, selected),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Start Run',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _difficultyColor(Difficulty d) => switch (d) {
        Difficulty.easy => const Color(0xFF4CAF50),
        Difficulty.medium => const Color(0xFFFF9800),
        Difficulty.hard => const Color(0xFFE53935),
      };

  String _difficultyDescription(Difficulty d) => switch (d) {
        Difficulty.easy => '15 second snippet',
        Difficulty.medium => '5 second snippet',
        Difficulty.hard => '1 second snippet',
      };

  String _difficultyMultiplier(Difficulty d) => switch (d) {
        Difficulty.easy => '×1.0',
        Difficulty.medium => '×1.5',
        Difficulty.hard => '×2.0',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Choose a category',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryColor,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(text: 'Genre'),
            Tab(text: 'Artist'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGenreTab(),
          _buildArtistTab(),
        ],
      ),
    );
  }

  Widget _buildGenreTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadCategories, child: const Text('Retry')),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.4,
      ),
      itemCount: _categories.length,
      itemBuilder: (context, i) => _buildCategoryCard(_categories[i]),
    );
  }

  Widget _buildCategoryCard(Category category) {
    final color = _categoryColor(category.category);
    return GestureDetector(
      onTap: () => _startWithCategory(category),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, color.withOpacity(0.6)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -10,
              bottom: -10,
              child: Icon(
                _categoryIcon(category.category),
                size: 70,
                color: Colors.white.withOpacity(0.12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_categoryIcon(category.category), color: Colors.white, size: 28),
                  const Spacer(),
                  Text(
                    category.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${category.trackCount} songs',
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtistTab() {
    final showSearch = _artistController.text.trim().length >= 2;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _artistController,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search artist...',
              hintStyle: const TextStyle(color: AppTheme.textSecondary),
              prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
              suffixIcon: _isSearchingArtists
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _artistController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: AppTheme.textSecondary),
                          onPressed: () {
                            _artistController.clear();
                            setState(() => _artistResults = []);
                          },
                        )
                      : null,
              filled: true,
              fillColor: AppTheme.surfaceColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: showSearch
              ? _buildSearchResults()
              : _buildArtistSuggestions(),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_artistResults.isEmpty) {
      return const Center(
        child: Text('No artists found', style: TextStyle(color: AppTheme.textSecondary)),
      );
    }
    return ListView.builder(
      itemCount: _artistResults.length,
      itemBuilder: (context, i) => _buildArtistTile(
        _artistResults[i],
        showFavButton: true,
      ),
    );
  }

  Widget _buildArtistSuggestions() {
    if (_isLoadingArtistData) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (_favourites.isNotEmpty) ...[
          _buildSectionHeader('Your favourites', Icons.favorite_rounded),
          ..._favourites.map((a) => _buildArtistTile(a, showFavButton: true)),
          const SizedBox(height: 8),
        ],
        if (_trending.isNotEmpty) ...[
          _buildSectionHeader('Trending', Icons.trending_up_rounded),
          ..._trending
              .where((a) => !_favourites.contains(a))
              .map((a) => _buildArtistTile(a, showFavButton: true)),
        ],
        if (_favourites.isEmpty && _trending.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text(
                'Search for an artist above',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryColor),
          const SizedBox(width: 6),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: AppTheme.primaryColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArtistTile(ArtistInfo artist, {bool showFavButton = false}) {
    final isFav = _favourites.contains(artist);
    final pic = artist.pictureUrl;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppTheme.primaryColor.withOpacity(0.2),
        backgroundImage: pic != null ? NetworkImage(pic) : null,
        onBackgroundImageError: pic != null ? (_, __) {} : null,
        child: pic == null
            ? const Icon(Icons.person_rounded, color: AppTheme.primaryColor, size: 20)
            : null,
      ),
      title: Text(artist.name, style: const TextStyle(color: AppTheme.textPrimary)),
      trailing: showFavButton
          ? IconButton(
              icon: Icon(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFav ? AppTheme.primaryColor : AppTheme.textSecondary,
                size: 20,
              ),
              onPressed: () => _toggleFavourite(artist),
            )
          : const Icon(Icons.arrow_forward_ios_rounded,
              color: AppTheme.textSecondary, size: 14),
      onTap: () => _startWithArtist(artist),
    );
  }

  Color _categoryColor(String? category) {
    switch (category) {
      case 'pop': return const Color(0xFFE91E8C);
      case 'hiphop': return const Color(0xFF9C27B0);
      case 'rock': return const Color(0xFFE53935);
      case 'electro': return const Color(0xFF00BCD4);
      case 'dance': return const Color(0xFFFF9800);
      case 'rnb': return const Color(0xFF795548);
      case 'kpop': return const Color(0xFFEC407A);
      case 'rap_fr': return const Color(0xFF3F51B5);
      case 'variete_fr': return const Color(0xFF009688);
      case 'reggaeton': return const Color(0xFF4CAF50);
      case 'latin': return const Color(0xFFFF5722);
      case 'afrobeats': return const Color(0xFFFFC107);
      case 'jpop': return const Color(0xFFF48FB1);
      case 'bollywood': return const Color(0xFFFF7043);
      default: return AppTheme.primaryColor;
    }
  }

  IconData _categoryIcon(String? category) {
    switch (category) {
      case 'pop': return Icons.star_rounded;
      case 'hiphop': return Icons.mic_rounded;
      case 'rock': return Icons.electric_bolt_rounded;
      case 'electro': return Icons.headphones_rounded;
      case 'dance': return Icons.nightlife_rounded;
      case 'rnb': return Icons.favorite_rounded;
      case 'kpop': return Icons.auto_awesome_rounded;
      case 'rap_fr': return Icons.record_voice_over_rounded;
      case 'variete_fr': return Icons.music_note_rounded;
      case 'reggaeton': return Icons.wb_sunny_rounded;
      case 'latin': return Icons.local_fire_department_rounded;
      case 'afrobeats': return Icons.celebration_rounded;
      case 'jpop': return Icons.spa_rounded;
      case 'bollywood': return Icons.movie_rounded;
      default: return Icons.library_music_rounded;
    }
  }
}
