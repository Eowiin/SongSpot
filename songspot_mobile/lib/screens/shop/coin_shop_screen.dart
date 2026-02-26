import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/coin_product.dart';
import '../../providers/auth_provider.dart';
import '../../providers/coin_shop_provider.dart';

class CoinShopScreen extends StatefulWidget {
  const CoinShopScreen({super.key});

  @override
  State<CoinShopScreen> createState() => _CoinShopScreenState();
}

class _CoinShopScreenState extends State<CoinShopScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shopProvider = context.read<CoinShopProvider>();
      shopProvider.initialize();
      shopProvider.loadProducts();
    });
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
      appBar: AppBar(
        title: const Text('Coin Shop'),
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
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
                            borderRadius: BorderRadius.circular(AppTheme.borderRadius),
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
                            borderRadius: BorderRadius.circular(AppTheme.borderRadius),
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

                      ...shopProvider.products.map((product) {
                        return _buildProductCard(context, product, shopProvider);
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
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
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
                    if (product.bonusLabel != null && product.bonusLabel!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          product.bonusLabel!,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
            child: Text(
              shopProvider.isPurchasing ? '...' : storePrice,
            ),
          ),
        ],
      ),
    );
  }
}
