import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../config/admob_config.dart';
import '../../l10n/app_localizations.dart';
import '../../models/pack.dart';
import '../../models/room.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pack_provider.dart';
import '../../providers/room_provider.dart';
import '../../services/admob_service.dart';
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
  String? _selectedCategory;
  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;
  bool? _lastHasNoAds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PackProvider>().loadPacks(widget.roomId);
      _maybeLoadBanner();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hasNoAds = context.watch<AuthProvider>().user?.hasNoAds ?? false;
    if (_lastHasNoAds == hasNoAds) return;
    _lastHasNoAds = hasNoAds;

    if (hasNoAds) {
      _bannerAd?.dispose();
      _bannerAd = null;
      _isBannerLoaded = false;
    } else {
      _maybeLoadBanner();
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  void _maybeLoadBanner() {
    if (_bannerAd != null) return;
    final hasNoAds = context.read<AuthProvider>().user?.hasNoAds ?? false;
    if (!AdMobService().canServeAds(adsDisabled: hasNoAds)) return;

    final banner = BannerAd(
      adUnitId: AdMobConfig.bannerPackListAdUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _isBannerLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _bannerAd = null;
            _isBannerLoaded = false;
          });
        },
      ),
    );

    banner.load();
    _bannerAd = banner;
  }

  List<SongPack> _filteredPacks(List<SongPack> packs) {
    final filtered = _selectedCategory == null
        ? List<SongPack>.from(packs)
        : packs.where((p) => p.category == _selectedCategory).toList();
    filtered.sort((a, b) {
      if (a.isOwned != b.isOwned) {
        return a.isOwned ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return filtered;
  }

  /// Returns the sorted list of distinct category keys present in the pack list.
  List<String> _availableCategories(List<SongPack> packs) {
    final keys = packs
        .map((p) => p.category)
        .whereType<String>()
        .toSet()
        .toList();
    keys.sort(
      (a, b) => (_categoryLabels[a] ?? a).compareTo(_categoryLabels[b] ?? b),
    );
    return keys;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final packProvider = context.watch<PackProvider>();
    final showLoadingState =
        packProvider.isLoading && packProvider.packs.isEmpty;
    final hasNoAds = context.watch<AuthProvider>().user?.hasNoAds ?? false;
    final canServeAds = AdMobService().canServeAds(adsDisabled: hasNoAds);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.packListTitle)),
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
                      l10n.packBrowseTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
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
                        if (canServeAds && _bannerAd != null && _isBannerLoaded)
                          _buildBannerSlot(),
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

  Widget _buildBannerSlot() {
    final banner = _bannerAd;
    if (banner == null || !_isBannerLoaded) return const SizedBox.shrink();

    return KeyedSubtree(
      key: ObjectKey(banner),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
        ),
        child: SizedBox(
          width: banner.size.width.toDouble(),
          height: banner.size.height.toDouble(),
          child: AdWidget(key: ObjectKey(banner), ad: banner),
        ),
      ),
    );
  }

  Widget _buildCategoryFilter(List<SongPack> packs) {
    final l10n = AppLocalizations.of(context);
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
              label: Text(l10n.packFilterAll),
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
    final l10n = AppLocalizations.of(context);
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
                  l10n.coinsAmount(coins),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: Colors.white),
                ),
                Text(
                  l10n.packNeedMoreCoins,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const CoinShopScreen()));
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(l10n.packGetCoins),
          ),
        ],
      ),
    );
  }

  Widget _buildPackCard(BuildContext context, SongPack pack) {
    final l10n = AppLocalizations.of(context);
    final priceLabel = pack.isFree || pack.priceCoins == 0
        ? l10n.packPriceFree
        : l10n.packCoinsPrice(pack.priceCoins);
    final metaParts = <String>['${pack.trackCount} tracks'];
    if (pack.category != null) {
      metaParts.add(_categoryLabels[pack.category!] ?? pack.category!);
    }
    if (!pack.isOwned) {
      metaParts.add(priceLabel);
    }
    final progressCopy = pack.isActive
        ? (pack.currentDay != null && pack.totalDays > 0
              ? l10n.packProgressDay(pack.currentDay!, pack.totalDays)
              : l10n.packStateInProgress)
        : pack.isCompleted
        ? l10n.packStateFinishedInRoom
        : pack.canActivate
        ? l10n.packStateReadyNow
        : pack.isOwned
        ? l10n.packStateAfterActivePack
        : priceLabel;
    final statusColor = pack.isActive
        ? AppTheme.accentColor
        : pack.canActivate
        ? AppTheme.successColor
        : AppTheme.textSecondary;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
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
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      metaParts.join(' • '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      progressCopy,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 40,
                child: ElevatedButton(
                  onPressed: _isPackActionEnabled(pack)
                      ? () => _handlePackPrimaryAction(pack)
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: Text(_packPrimaryLabel(pack)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _packPrimaryLabel(SongPack pack) {
    final l10n = AppLocalizations.of(context);
    if (!pack.isOwned) {
      return pack.isFree || pack.priceCoins == 0
          ? l10n.packActionUnlock
          : l10n.packActionBuy;
    }
    if (pack.isActive) return l10n.packActionInProgress;
    if (pack.isCompleted) return l10n.packActionFinished;
    if (pack.canActivate) return l10n.packActionActivate;
    return l10n.packActionLater;
  }

  bool _isPackActionEnabled(SongPack pack) {
    if (!pack.isOwned) return true;
    if (pack.isActive) return false;
    if (pack.isCompleted) return false;
    return pack.canActivate;
  }

  Future<void> _handlePackPrimaryAction(SongPack pack) async {
    final l10n = AppLocalizations.of(context);
    if (pack.isOwned) {
      final activateResponse = await context.read<PackProvider>().activatePack(
        roomId: widget.roomId,
        packId: pack.id,
      );
      if (!mounted) return;
      if (activateResponse != null) {
        final roomJson = activateResponse['room'] as Map<String, dynamic>?;
        if (roomJson != null) {
          context.read<RoomProvider>().setCurrentRoom(Room.fromJson(roomJson));
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              activateResponse['message'] as String? ??
                  l10n.packActivatedSuccessfully,
            ),
            backgroundColor: AppTheme.successColor,
          ),
        );
      } else {
        final errorMessage = context.read<PackProvider>().errorMessage;
        if (errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage.replaceFirst('Exception: ', '')),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
      return;
    }

    final purchaseResponse = await context.read<PackProvider>().purchasePack(
      roomId: widget.roomId,
      packId: pack.id,
    );
    if (!mounted) return;

    if (purchaseResponse != null) {
      final newCoins = purchaseResponse['coins'] as int?;
      if (newCoins != null) {
        context.read<AuthProvider>().updateCoinsBalance(newCoins);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.packUnlockedActivateWhenReady),
          backgroundColor: AppTheme.successColor,
        ),
      );
      return;
    }

    final errorMessage = context.read<PackProvider>().errorMessage;
    if (errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage.replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
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
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.album, color: AppTheme.primaryColor),
        ),
      ),
    );
  }
}
