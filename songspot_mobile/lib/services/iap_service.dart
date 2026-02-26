import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'api_service.dart';

class IAPService {
  static final IAPService _instance = IAPService._();
  factory IAPService() => _instance;
  IAPService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  final ApiService _apiService = ApiService();
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  List<ProductDetails> _products = [];
  List<String> _notFoundIds = [];
  bool _isAvailable = false;
  final Set<String> _processingTransactions = {};

  /// Callbacks for purchase results
  void Function(int coinsAdded, int totalCoins)? onCoinsAdded;
  void Function(String error)? onError;
  void Function()? onPurchaseStarted;
  void Function()? onCanceled;

  static const Set<String> productIds = {
    'com.songspot.coins.500',
    'com.songspot.coins.1200',
    'com.songspot.coins.3000',
    'com.songspot.coins.7000',
  };

  bool get isAvailable => _isAvailable;
  List<ProductDetails> get products => _products;
  List<String> get notFoundIds => _notFoundIds;

  Future<void> initialize() async {
    _isAvailable = await _iap.isAvailable();
    if (!_isAvailable) {
      debugPrint('IAP: Store not available');
      return;
    }

    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription?.cancel(),
      onError: (error) {
        debugPrint('IAP: Purchase stream error: $error');
        onError?.call(error.toString());
      },
    );

    await loadProducts();
  }

  Future<void> loadProducts() async {
    if (!_isAvailable) return;

    final response = await _iap.queryProductDetails(productIds);
    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('IAP: Products not found: ${response.notFoundIDs}');
    }
    if (response.error != null) {
      debugPrint('IAP: Query error: ${response.error!.message}');
    }

    _notFoundIds = response.notFoundIDs.toList();
    _products = response.productDetails.toList();
    _products.sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
  }

  Future<void> buyProduct(ProductDetails product) async {
    if (!_isAvailable) {
      onError?.call('Store not available');
      return;
    }

    final purchaseParam = PurchaseParam(productDetails: product);
    onPurchaseStarted?.call();
    await _iap.buyConsumable(purchaseParam: purchaseParam);
  }

  /// Find a ProductDetails by its store product ID
  ProductDetails? getProductById(String productId) {
    try {
      return _products.firstWhere((p) => p.id == productId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyAndCreditPurchase(purchase);
          break;
        case PurchaseStatus.error:
          debugPrint('IAP: Purchase error: ${purchase.error?.message}');
          onError?.call(_friendlyError(purchase.error));
          break;
        case PurchaseStatus.canceled:
          debugPrint('IAP: Purchase canceled');
          onCanceled?.call();
          break;
        case PurchaseStatus.pending:
          debugPrint('IAP: Purchase pending');
          break;
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<void> _verifyAndCreditPurchase(PurchaseDetails purchase) async {
    final txId = purchase.purchaseID ?? '';
    if (_processingTransactions.contains(txId)) return;
    _processingTransactions.add(txId);
    try {
      final store = Platform.isIOS ? 'apple' : 'google';
      final result = await _apiService.verifyIAP(
        store: store,
        productId: purchase.productID,
        receiptData: purchase.verificationData.serverVerificationData,
        transactionId: txId,
      );

      final coinsAdded = result['coins_credited'] as int? ?? 0;
      final totalCoins = result['coins'] as int? ?? 0;
      onCoinsAdded?.call(coinsAdded, totalCoins);
    } catch (e) {
      debugPrint('IAP: Verification error: $e');
      onError?.call('Purchase verification failed. Your coins will be credited shortly.');
    } finally {
      _processingTransactions.remove(txId);
    }
  }

  String _friendlyError(IAPError? error) {
    final msg = error?.message?.toLowerCase() ?? '';
    if (msg.contains('cancel') || msg.contains('user cancel')) {
      return 'Purchase was cancelled.';
    }
    if (msg.contains('network') || msg.contains('connection') || msg.contains('internet')) {
      return 'Payment failed. Please check your connection and try again.';
    }
    if (msg.contains('already owned') || msg.contains('item already')) {
      return 'This item was already purchased.';
    }
    return 'Payment failed. Please try again.';
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
