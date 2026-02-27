import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/pack.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pack_provider.dart';
import '../shop/coin_shop_screen.dart';

// Display labels for each category key returned by the backend
const _categoryLabels = <String, String>{
  'pop': 'Pop',
  'hiphop': 'Hip-Hop / Rap',
  'rock': 'Rock',
  'electro': 'Électro',
  'dance': 'Dance',
  'rnb': 'R&B',
  'kpop': 'K-pop',
  'rap_fr': 'Rap FR',
  'variete_fr': 'Variété FR',
  'reggaeton': 'Reggaeton',
  'latin': 'Latin Pop',
  'afrobeats': 'Afrobeats',
  'jpop': 'J-pop',
  'bollywood': 'Bollywood',
};

class PackListScreen extends StatefulWidget {
  final String roomId;

  const PackListScreen({super.key, required this.roomId});

  @override
  State<PackListScreen> createState() => _PackListScreenState();
}

class _PackListScreenState extends State<PackListScreen> {
  final Set<String> _purchasingPackIds = {};
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PackProvider>().loadPacks(widget.roomId);
    });
  }

  List<SongPack> _filteredPacks(List<SongPack> packs) {
    if (_selectedCategory == null) return packs;
    return packs.where((p) => p.category == _selectedCategory).toList();
  }

  /// Returns the sorted list of distinct category keys present in the pack list.
  List<String> _availableCategories(List<SongPack> packs) {
    final keys = packs
        .map((p) => p.category)
        .whereType<String>()
        .toSet()
        .toList();
    keys.sort((a, b) => (_categoryLabels[a] ?? a).compareTo(_categoryLabels[b] ?? b));
    return keys;
  }

  @override
  Widget build(BuildContext context) {
    final packProvider = context.watch<PackProvider>();
    final showLoadingState = packProvider.isLoading && packProvider.packs.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Song Packs'),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: showLoadingState
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: AppTheme.pagePadding.copyWith(bottom: 8),
                    child: Text(
                      'Browse packs',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  if (packProvider.errorMessage != null)
                    Padding(
                      padding: AppTheme.pagePadding.copyWith(top: 0, bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.errorColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                        ),
                        child: Text(
                          packProvider.errorMessage!,
                          style: const TextStyle(color: AppTheme.errorColor),
                        ),
                      ),
                    ),
                  // Category filter chips
                  _buildCategoryFilter(packProvider.packs),
                  // Pack list
                  Expanded(
                    child: ListView(
                      padding: AppTheme.pagePadding.copyWith(top: 12),
                      children: [
                        _buildGetMoreCoinsBanner(context),
                        ..._filteredPacks(packProvider.packs).map((pack) {
                          return _buildPackCard(context, pack);
                        }),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildCategoryFilter(List<SongPack> packs) {
    final categories = _availableCategories(packs);
    if (categories.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // "All" chip
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('All'),
              selected: _selectedCategory == null,
              onSelected: (_) => setState(() => _selectedCategory = null),
            ),
          ),
          ...categories.map((key) {
            final label = _categoryLabels[key] ?? key;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(label),
                selected: _selectedCategory == key,
                onSelected: (_) => setState(() {
                  _selectedCategory = _selectedCategory == key ? null : key;
                }),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildGetMoreCoinsBanner(BuildContext context) {
    final coins = context.watch<AuthProvider>().user?.coins ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
      ),
      child: Row(
        children: [
          const Icon(Icons.monetization_on, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$coins coins',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
                ),
                Text(
                  'Need more coins?',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CoinShopScreen()),
              );
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text('Get Coins'),
          ),
        ],
      ),
    );
  }

  Widget _buildPackCard(BuildContext context, SongPack pack) {
    final priceLabel = pack.isFree || pack.priceCoins == 0 ? 'Free' : '${pack.priceCoins} coins';
    final description = pack.description.isEmpty ? 'Stem Pack' : pack.description;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPackIcon(pack.iconUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pack.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${pack.trackCount} tracks • $priceLabel',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (pack.category != null)
                _buildTag(
                  context,
                  _categoryLabels[pack.category!] ?? pack.category!,
                  AppTheme.primaryColor,
                ),
              if (pack.isFeatured) _buildTag(context, 'Featured', AppTheme.primaryColor),
              if (pack.isOwned) _buildTag(context, 'Owned', AppTheme.successColor),
              if (pack.isFree || pack.priceCoins == 0)
                _buildTag(context, 'Free', AppTheme.secondaryColor),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: pack.isOwned || _purchasingPackIds.contains(pack.id)
                  ? null
                  : () async {
                      setState(() {
                        _purchasingPackIds.add(pack.id);
                      });
                      final success = await context.read<PackProvider>().purchasePack(
                            roomId: widget.roomId,
                            packId: pack.id,
                          );
                      if (success && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Purchased ${pack.name}'),
                            backgroundColor: AppTheme.successColor,
                          ),
                        );
                      }
                      if (mounted) {
                        setState(() {
                          _purchasingPackIds.remove(pack.id);
                        });
                      }
                    },
              child: Text(
                pack.isOwned
                    ? 'Owned'
                    : _purchasingPackIds.contains(pack.id)
                        ? 'Buying...'
                        : 'Buy',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
      ),
    );
  }

  Widget _buildPackIcon(String? iconUrl) {
    if (iconUrl == null || iconUrl.isEmpty) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Icon(Icons.album, color: AppTheme.primaryColor),
      );
    }

    return SizedBox(
      width: 48,
      height: 48,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          iconUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.album,
            color: AppTheme.primaryColor,
          ),
        ),
      ),
    );
  }
}
