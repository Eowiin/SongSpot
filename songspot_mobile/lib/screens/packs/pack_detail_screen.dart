import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/pack.dart';
import '../../providers/auth_provider.dart';
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
    final purchaseResponse = await context.read<PackProvider>().purchasePack(
      roomId: widget.roomId,
      packId: widget.packId,
    );
    if (purchaseResponse != null && mounted) {
      final newCoins = purchaseResponse['coins'] as int?;
      if (newCoins != null) {
        context.read<AuthProvider>().updateCoinsBalance(newCoins);
      }
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
      appBar: AppBar(title: Text(widget.packName)),
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
                  const SizedBox(height: 8),
                  Text(
                    '${pack.trackCount} tracks • ${pack.isFree || pack.priceCoins == 0 ? 'Free' : '${pack.priceCoins} coins'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
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
                ],
              ),
      ),
    );
  }
}
