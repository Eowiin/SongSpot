import '../../services/search_updates.dart';
import '../../widgets/search_status_text.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../config/category_style.dart';
import '../../config/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/artist_info.dart';
import '../../models/category.dart';
import '../../models/solo_setup.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/pressable.dart';
import '../auth/login_screen.dart';

/// The categories a run can be played from: every one that has tracks.
Future<List<Category>> fetchStockedCategories() async {
  final data = await ApiService().getCategories();
  return data
      .map((j) => Category.fromJson(j as Map<String, dynamic>))
      .where((c) => c.trackCount > 0)
      .toList();
}

/// The style of the next solo run: every genre, one category, or an artist.
///
/// Opened from the style row of the solo panel. It returns the chosen setup to
/// the panel and keeps the difficulty the player already set.
///
/// The search field at the top is a real field. Typing an artist's name
/// replaces the list of styles with matching artists, so the screen never
/// sends the player somewhere else to search. With the field empty, it lists
/// every genre, the categories and the player's favourite artists.
class StylePickerScreen extends StatefulWidget {
  const StylePickerScreen({
    super.key,
    required this.current,
    required this.categories,
  });

  final SoloSetup current;

  /// The panel's request for the categories, reused rather than repeated.
  /// Two requests fired at once used to race each other through a token
  /// refresh, and the loser showed nothing but a retry button.
  final Future<List<Category>> categories;

  @override
  State<StylePickerScreen> createState() => _StylePickerScreenState();
}

class _StylePickerScreenState extends State<StylePickerScreen> {
  final ApiService _api = ApiService();
  late Future<List<Category>> _categories = widget.categories;

  final TextEditingController _query = TextEditingController();
  Timer? _searchDebounce;
  int _searchId = 0;
  List<ArtistInfo> _results = [];
  bool _searching = false;
  SearchStatus _searchStatus = SearchStatus.idle;

  List<ArtistInfo> _favourites = [];

  bool get _showingSearch => _query.text.trim().length >= 2;

  @override
  void initState() {
    super.initState();
    _query.addListener(_onQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadFavourites();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// Favourites need an account, so a guest skips the call instead of
  /// collecting a 401.
  Future<void> _loadFavourites() async {
    if (context.read<AuthProvider>().isGuest) return;
    try {
      final rows = await _api.getFavouriteArtists();
      if (!mounted) return;
      setState(() {
        // Growable, never `const []`: _toggleFavourite inserts into it.
        _favourites = rows
            .map((j) => ArtistInfo.fromJson(j as Map<String, dynamic>))
            .toList();
      });
    } catch (_) {
      // The list simply stays empty.
    }
  }

  /// Search as the player types, with a debounce. A response that arrives
  /// after a newer keystroke is dropped, so the answer to `ro` cannot land on
  /// top of the answer to `rosalia`.
  void _onQueryChanged() {
    _searchDebounce?.cancel();
    final id = ++_searchId;
    final q = _query.text.trim();
    if (q.length < 2) {
      setState(() {
        _results = [];
        _searching = false;
        _searchStatus = SearchStatus.idle;
      });
      return;
    }
    setState(() { _searching = true; _results = []; _searchStatus = SearchStatus.loading; });
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        await for (final page in _api.watchSearch(q, artists: true,
            isActive: () => mounted && id == _searchId)) {
          if (!mounted || id != _searchId) return;
          setState(() {
            _results = page.results.map((j) => ArtistInfo.fromJson(j as Map<String, dynamic>)).toList();
            _searchStatus = page.status;
            _searching = false;
          });
        }
      } catch (_) {
        if (!mounted || id != _searchId) return;
        setState(() { _searchStatus = SearchStatus.unavailable; _searching = false; });
      }
    });
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
        await _api.addFavouriteArtist(artist.name, artistDeezerId: artist.deezerId);
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
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text(
          l10n.signInRequired,
          style: const TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          l10n.categorySignInForFavourites,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: Text(
              l10n.signIn,
              style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _choose(SoloSetup setup) => Navigator.pop(context, setup);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(l10n.soloStyle.toUpperCase()),
      ),
      body: ResponsiveCenter(
        maxWidth: 760,
        padding: EdgeInsets.symmetric(horizontal: context.pageGutter * 0.4),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: l10n.categorySearchArtistHint,
                  hintStyle: const TextStyle(color: AppTheme.textSecondary),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _query.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: AppTheme.textSecondary),
                              onPressed: _query.clear,
                            )
                          : null,
                  filled: true,
                  fillColor: AppTheme.surfaceColor,
                ),
              ),
            ),
            Expanded(
              child: _showingSearch ? _buildResults(l10n) : _buildStyles(l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(AppLocalizations l10n) {
    return Column(children: [
      SearchStatusText(status: _searchStatus),
      Expanded(child: ListView.builder(
        padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom),
        itemCount: _results.length,
        itemBuilder: (context, i) => _artistTile(_results[i]),
      )),
    ]);
  }

  Widget _buildStyles(AppLocalizations l10n) {
    final current = widget.current;
    return FutureBuilder<List<Category>>(
      future: _categories,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        return ListView(
          padding: EdgeInsets.fromLTRB(
              0, 4, 0, 12 + MediaQuery.viewPaddingOf(context).bottom),
          children: [
            if (current.artistName != null)
              _option(
                label: current.artistName!,
                icon: Icons.person_rounded,
                color: AppTheme.secondaryColor,
                selected: true,
                onTap: () => _choose(current),
              ),
            _option(
              label: l10n.mixLabel,
              icon: Icons.shuffle_rounded,
              color: AppTheme.primaryColor,
              selected: current.isMix,
              onTap: () => _choose(current.withMix()),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.primaryColor),
                ),
              )
            else if (snapshot.hasError)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: TextButton(
                    onPressed: () => setState(() => _categories = fetchStockedCategories()),
                    child: Text(l10n.retry),
                  ),
                ),
              )
            else
              for (final category in snapshot.data!)
                _option(
                  label: category.name,
                  icon: categoryIcon(category.category),
                  color: categoryColor(category.category),
                  selected: current.category?.id == category.id,
                  onTap: () => _choose(current.withCategory(category)),
                ),
            if (_favourites.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: SectionLabel(
                  l10n.categoryYourFavourites,
                  icon: Icons.favorite_rounded,
                  color: AppTheme.secondaryColor,
                ),
              ),
              ..._favourites.map(_artistTile),
            ],
          ],
        );
      },
    );
  }

  Widget _option({
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: Icon(
        selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
        color: selected ? AppTheme.primaryColor : AppTheme.ink3,
        size: 20,
      ),
      onTap: onTap,
    );
  }

  Widget _artistTile(ArtistInfo artist) {
    final isFav = _favourites.contains(artist);
    final pic = artist.pictureUrl;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.2),
        backgroundImage: pic != null ? NetworkImage(pic) : null,
        onBackgroundImageError: pic != null ? (_, _) {} : null,
        child: pic == null
            ? const Icon(Icons.person_rounded, color: AppTheme.primaryColor, size: 20)
            : null,
      ),
      title: Text(artist.name, style: const TextStyle(color: AppTheme.textPrimary)),
      trailing: IconButton(
        icon: Icon(
          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: isFav ? AppTheme.primaryColor : AppTheme.textSecondary,
          size: 20,
        ),
        onPressed: () => _toggleFavourite(artist),
      ),
      onTap: () => _choose(widget.current.withArtist(artist.name, artist.deezerId)),
    );
  }
}
