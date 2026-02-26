import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../models/coin_product.dart';
import '../services/api_service.dart';
import '../services/iap_service.dart';
import 'auth_provider.dart';

class CoinShopProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final IAPService _iapService = IAPService();
  AuthProvider? _authProvider;

  List<CoinProduct> _products = [];
  bool _isLoading = false;
  bool _isPurchasing = false;
  Timer? _purchaseTimeout;
  /// Load/init error shown as a persistent banner.
  String? _errorMessage;
  /// Purchase-specific error shown as a dismissable snackbar.
  String? _purchaseError;
  int? _lastCoinsAdded;

  List<CoinProduct> get products => _products;
  bool get isLoading => _isLoading;
  bool get isPurchasing => _isPurchasing;
  String? get errorMessage => _errorMessage;
  String? get purchaseError => _purchaseError;
  int? get lastCoinsAdded => _lastCoinsAdded;
  bool get isStoreAvailable => _iapService.isAvailable;
  /// True when the store is reachable but none of the products were found.
  /// Means products aren't created/active in App Store Connect or Play Console.
  bool get storeProductsNotFound =>
      _iapService.isAvailable &&
      _iapService.notFoundIds.isNotEmpty &&
      _iapService.products.isEmpty;

  CoinShopProvider() {
    _iapService.onCoinsAdded = _onCoinsAdded;
    _iapService.onError = _onError;
    _iapService.onCanceled = _onCanceled;
    _iapService.onPurchaseStarted = _onPurchaseStarted;
  }

  void setAuthProvider(AuthProvider auth) {
    _authProvider = auth;
  }

  Future<void> initialize() async {
    await _iapService.initialize();
  }

  Future<void> loadProducts() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // Load products from backend (coin amounts, names, labels)
      final response = await _apiService.getCoinProducts();
      _products = response
          .map((item) => CoinProduct.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get the store price for a product (from Apple/Google)
  String getStorePrice(CoinProduct product) {
    final storeProduct = _iapService.getProductById(product.productId);
    if (storeProduct != null) {
      return storeProduct.price;
    }
    // Fallback to backend display price
    return product.priceDisplay;
  }

  /// Get the store ProductDetails for a CoinProduct
  ProductDetails? getStoreProduct(CoinProduct product) {
    return _iapService.getProductById(product.productId);
  }

  Future<void> purchaseProduct(CoinProduct product) async {
    final storeProduct = _iapService.getProductById(product.productId);
    if (storeProduct == null) {
      _errorMessage = 'Product not available in store';
      notifyListeners();
      return;
    }

    _errorMessage = null;
    _lastCoinsAdded = null;
    notifyListeners();

    await _iapService.buyProduct(storeProduct);
  }

  void _onPurchaseStarted() {
    _isPurchasing = true;
    _purchaseTimeout?.cancel();
    _purchaseTimeout = Timer(const Duration(minutes: 3), () {
      if (_isPurchasing) {
        _isPurchasing = false;
        _purchaseError = 'Payment timed out. Check your purchase history or try again.';
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void _onCoinsAdded(int coinsAdded, int totalCoins) {
    _purchaseTimeout?.cancel();
    _isPurchasing = false;
    _lastCoinsAdded = coinsAdded;
    _errorMessage = null;
    // Update the user's coin balance immediately using the value returned
    // by the backend — no extra API call needed.
    _authProvider?.updateCoinsBalance(totalCoins);
    notifyListeners();
  }

  void _onCanceled() {
    _purchaseTimeout?.cancel();
    _isPurchasing = false;
    notifyListeners();
  }

  void _onError(String error) {
    _purchaseTimeout?.cancel();
    _isPurchasing = false;
    _purchaseError = error;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void clearPurchaseError() {
    _purchaseError = null;
    notifyListeners();
  }

  void clearLastCoinsAdded() {
    _lastCoinsAdded = null;
    notifyListeners();
  }
}
