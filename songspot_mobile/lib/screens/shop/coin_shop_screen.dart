import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../config/admob_config.dart';
import '../../models/coin_product.dart';
import '../../providers/auth_provider.dart';
import '../../providers/coin_shop_provider.dart';
import '../../services/admob_service.dart';
import '../../services/api_service.dart';

class CoinShopScreen extends StatefulWidget {
  const CoinShopScreen({super.key});

  @override
  State<CoinShopScreen> createState() => _CoinShopScreenState();
}

class _CoinShopScreenState extends State<CoinShopScreen> {
  final ApiService _apiService = ApiService();
  bool _rewardClaimInProgress = false;
  bool _rewardStatusLoading = false;
  int? _rewardDailyCap;
  int? _rewardRemainingToday;
  int? _rewardCoinsPerClaim;
  int? _lastRewardCoinsEarned;
  Timer? _rewardFeedbackTimer;
  BannerAd? _bannerAd;
  bool _isBannerReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shopProvider = context.read<CoinShopProvider>();
      shopProvider.initialize();
      shopProvider.loadProducts();
      final adsDisabled = context.read<AuthProvider>().user?.hasNoAds ?? false;
      unawaited(AdMobService().preloadRewarded(adsDisabled: adsDisabled));
      if (!adsDisabled) {
        _loadBannerAd();
      }
      unawaited(_loadRewardStatus());
    });
  }

  @override
  void dispose() {
    _rewardFeedbackTimer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  void _loadBannerAd() {
    _bannerAd?.dispose();
    _bannerAd = BannerAd(
      adUnitId: AdMobConfig.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _isBannerReady = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() => _isBannerReady = false);
        },
      ),
    )..load();
  }

  Future<void> _loadRewardStatus() async {
    if (!mounted) return;
    setState(() => _rewardStatusLoading = true);
    try {
      final status = await _apiService.getRewardedAdStatus();
      if (!mounted) return;
      setState(() {
        _rewardCoinsPerClaim =
            status['reward_coins'] as int? ?? _rewardCoinsPerClaim;
        _rewardDailyCap = status['daily_cap'] as int? ?? _rewardDailyCap;
        _rewardRemainingToday =
            status['remaining_today'] as int? ?? _rewardRemainingToday;
      });
    } catch (_) {
      // Keep previous state if status endpoint fails.
    } finally {
      if (mounted) {
        setState(() => _rewardStatusLoading = false);
      }
    }
  }

  Future<void> _handleWatchAdForCoins() async {
    if (_rewardClaimInProgress) return;
    setState(() => _rewardClaimInProgress = true);
    final authProvider = context.read<AuthProvider>();
    final adsDisabled = authProvider.user?.hasNoAds ?? false;

    try {
      final rewarded = await AdMobService().showRewarded(
        adsDisabled: adsDisabled,
        onRewardEarned: () async {
          final response = await _apiService.claimRewardedAd(
            placement: 'coin_shop_bonus',
          );
          if (!mounted) return;
          final coins = response['coins'] as int?;
          final coinsAwarded =
              response['coins_awarded'] as int? ?? _rewardCoinsPerClaim ?? 10;
          final dailyCap = response['daily_cap'] as int?;
          final remainingToday = response['remaining_today'] as int?;
          if (coins != null) {
            authProvider.updateCoinsBalance(coins);
          }
          setState(() {
            _rewardCoinsPerClaim = coinsAwarded;
            if (dailyCap != null) _rewardDailyCap = dailyCap;
            if (remainingToday != null) _rewardRemainingToday = remainingToday;
            _lastRewardCoinsEarned = coinsAwarded;
          });
          _rewardFeedbackTimer?.cancel();
          _rewardFeedbackTimer = Timer(const Duration(seconds: 4), () {
            if (!mounted) return;
            setState(() => _lastRewardCoinsEarned = null);
          });
        },
      );

      if (!rewarded && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ad not ready yet. Please try again in a moment.'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } finally {
      if (mounted) {
        await _loadRewardStatus();
        setState(() => _rewardClaimInProgress = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shopProvider = context.watch<CoinShopProvider>();
    final authProvider = context.watch<AuthProvider>();
    final coins = authProvider.user?.coins ?? 0;

    // Show purchase error as snackbar
    if (shopProvider.purchaseError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(shopProvider.purchaseError!),
              backgroundColor: AppTheme.errorColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
          shopProvider.clearPurchaseError();
        }
      });
    }

    // Show success snackbar when coins are added
    if (shopProvider.lastCoinsAdded != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('+${shopProvider.lastCoinsAdded} coins added!'),
              backgroundColor: AppTheme.successColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
          shopProvider.clearLastCoinsAdded();
          // Coin balance is already updated via CoinShopProvider._onCoinsAdded
          // → AuthProvider.updateCoinsBalance(). No extra API call needed.
        }
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Coin Shop')),
      bottomNavigationBar:
          (!(authProvider.user?.hasNoAds ?? false) &&
              _isBannerReady &&
              _bannerAd != null)
          ? SafeArea(
              top: false,
              child: SizedBox(
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
            )
          : null,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: AppTheme.backgroundGradient,
            ),
            child: shopProvider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: AppTheme.pagePadding,
                    children: [
                      // Coin balance header
                      _buildBalanceHeader(context, coins),
                      const SizedBox(height: 24),

                      if (!shopProvider.isStoreAvailable)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.errorColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(
                              AppTheme.borderRadius,
                            ),
                          ),
                          child: const Text(
                            'Store not available on this device.',
                            style: TextStyle(color: AppTheme.errorColor),
                          ),
                        ),

                      if (shopProvider.storeProductsNotFound)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(
                              AppTheme.borderRadius,
                            ),
                          ),
                          child: const Text(
                            'Products not found in store. Make sure in-app products are created and set to Active in App Store Connect / Play Console.',
                            style: TextStyle(color: Colors.orange),
                          ),
                        ),

                      Text(
                        'Get more coins',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Use coins to unlock song packs and hints.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),

                      if (!(authProvider.user?.hasNoAds ?? false)) ...[
                        _buildRewardedCard(context),
                        const SizedBox(height: 20),
                      ],

                      ...shopProvider.products.map((product) {
                        return _buildProductCard(
                          context,
                          product,
                          shopProvider,
                        );
                      }),
                    ],
                  ),
          ),
          // Payment processing overlay — blocks interaction and guides the user
          if (shopProvider.isPurchasing)
            const ModalBarrier(dismissible: false, color: Color(0x88000000)),
          if (shopProvider.isPurchasing)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Processing payment...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Please don't close the app",
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBalanceHeader(BuildContext context, int coins) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
      ),
      child: Row(
        children: [
          const Icon(Icons.monetization_on, size: 40, color: Colors.white),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your balance',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
              Text(
                '$coins coins',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(
    BuildContext context,
    CoinProduct product,
    CoinShopProvider shopProvider,
  ) {
    final storePrice = shopProvider.getStorePrice(product);
    final hasStoreProduct = shopProvider.getStoreProduct(product) != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: Row(
        children: [
          // Coin icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.monetization_on,
              color: AppTheme.primaryColor,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          // Product info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      product.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (product.bonusLabel != null &&
                        product.bonusLabel!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.secondaryColor.withValues(
                            alpha: 0.15,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          product.bonusLabel!,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: AppTheme.secondaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${product.coinsAmount} coins',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          // Buy button
          ElevatedButton(
            onPressed: shopProvider.isPurchasing || !hasStoreProduct
                ? null
                : () => shopProvider.purchaseProduct(product),
            child: Text(shopProvider.isPurchasing ? '...' : storePrice),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardedCard(BuildContext context) {
    final remaining = _rewardRemainingToday;
    final cap = _rewardDailyCap;
    final coinsPerClaim = _rewardCoinsPerClaim ?? 10;
    final limitReached = remaining != null && remaining <= 0;
    final buttonLabel = _rewardClaimInProgress
        ? 'Loading...'
        : limitReached
        ? 'Daily Limit Reached'
        : 'Watch Ad';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Free Bonus Coins',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Watch a rewarded ad to claim +$coinsPerClaim coins.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            cap == null || remaining == null
                ? (_rewardStatusLoading
                      ? 'Checking daily limit...'
                      : 'Daily limit unavailable right now.')
                : 'Remaining today: $remaining / $cap',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed:
                _rewardClaimInProgress || _rewardStatusLoading || limitReached
                ? null
                : _handleWatchAdForCoins,
            icon: const Icon(Icons.play_circle_outline),
            label: Text(buttonLabel),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _lastRewardCoinsEarned == null
                ? const SizedBox.shrink()
                : Container(
                    key: ValueKey('reward-feedback-$_lastRewardCoinsEarned'),
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.successColor.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          color: AppTheme.successColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '+$_lastRewardCoinsEarned coins added to your balance.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppTheme.successColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
