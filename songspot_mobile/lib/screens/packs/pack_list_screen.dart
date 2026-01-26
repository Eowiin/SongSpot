import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/pack.dart';
import '../../providers/pack_provider.dart';
import 'pack_detail_screen.dart';

class PackListScreen extends StatefulWidget {
  final String roomId;

  const PackListScreen({super.key, required this.roomId});

  @override
  State<PackListScreen> createState() => _PackListScreenState();
}

class _PackListScreenState extends State<PackListScreen> {
  final Set<String> _purchasingPackIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PackProvider>().loadPacks(widget.roomId);
    });
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
            : ListView(
                padding: AppTheme.pagePadding,
                children: [
                  Text(
                    'Browse today\'s packs',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Preview the tracklists before you unlock a pack.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  if (packProvider.errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
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
                  ...packProvider.packs.map((pack) {
                    return _buildPackCard(context, pack);
                  }),
                ],
              ),
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
              if (pack.isFeatured) _buildTag(context, 'Featured', AppTheme.primaryColor),
              if (pack.isOwned) _buildTag(context, 'Owned', AppTheme.successColor),
              if (pack.isFree || pack.priceCoins == 0)
                _buildTag(context, 'Free', AppTheme.secondaryColor),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PackDetailScreen(
                          roomId: widget.roomId,
                          packId: pack.id,
                          packName: pack.name,
                        ),
                      ),
                    );
                  },
                  child: const Text('Preview'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
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
