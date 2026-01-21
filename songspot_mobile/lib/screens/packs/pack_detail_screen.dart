import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/pack.dart';
import '../../providers/pack_provider.dart';
import 'pack_bundle_screen.dart';

class PackDetailScreen extends StatefulWidget {
  final String roomId;
  final String packId;
  final String packName;

  const PackDetailScreen({
    super.key,
    required this.roomId,
    required this.packId,
    required this.packName,
  });

  @override
  State<PackDetailScreen> createState() => _PackDetailScreenState();
}

class _PackDetailScreenState extends State<PackDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PackProvider>().loadPackDetail(
            roomId: widget.roomId,
            packId: widget.packId,
          );
    });
  }

  Future<void> _purchaseAndPlay(SongPack pack) async {
    final success = await context.read<PackProvider>().purchasePack(
          roomId: widget.roomId,
          packId: widget.packId,
        );
    if (success && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PackBundleScreen(
            roomId: widget.roomId,
            packId: widget.packId,
            packName: widget.packName,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final packProvider = context.watch<PackProvider>();
    final pack = packProvider.currentPack;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.packName),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: packProvider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : pack == null
                ? Center(
                    child: Text(
                      packProvider.errorMessage ?? 'Pack unavailable',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  )
                : ListView(
                    padding: AppTheme.pagePadding,
                    children: [
                      Text(
                        pack.description.isEmpty ? 'Stem Pack' : pack.description,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      if (pack.isOwned)
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PackBundleScreen(
                                  roomId: widget.roomId,
                                  packId: widget.packId,
                                  packName: widget.packName,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.play_circle_fill),
                          label: const Text('Play Daily Pack'),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: () => _purchaseAndPlay(pack),
                          icon: const Icon(Icons.lock_open),
                          label: Text(
                            pack.isFree || pack.priceCoins == 0
                                ? 'Unlock & Play'
                                : 'Buy & Play (${pack.priceCoins} coins)',
                          ),
                        ),
                      const SizedBox(height: 24),
                      ..._buildTrackCards(pack.tracks ?? []),
                    ],
                  ),
      ),
    );
  }

  List<Widget> _buildTrackCards(List<PackTrack> tracks) {
    if (tracks.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: AppTheme.cardGradient,
            borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
          ),
          child: const Text('No tracks in this pack yet.'),
        ),
      ];
    }

    return tracks.map((packTrack) {
      final track = packTrack.track;
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppTheme.cardGradient,
          borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
        ),
        child: Row(
          children: [
            _buildCover(track.coverUrl, packTrack.orderInPack),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    track.artist,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildCover(String? url, int order) {
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.backgroundColor,
        child: Text(
          order.toString(),
          style: const TextStyle(color: AppTheme.primaryColor),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => CircleAvatar(
          radius: 24,
          backgroundColor: AppTheme.backgroundColor,
          child: Text(
            order.toString(),
            style: const TextStyle(color: AppTheme.primaryColor),
          ),
        ),
      ),
    );
  }
}
