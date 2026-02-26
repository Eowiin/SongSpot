import 'package:equatable/equatable.dart';

class CoinProduct extends Equatable {
  final String id;
  final String productId;
  final String name;
  final int coinsAmount;
  final String priceDisplay;
  final String? bonusLabel;
  final int sortOrder;

  const CoinProduct({
    required this.id,
    required this.productId,
    required this.name,
    required this.coinsAmount,
    required this.priceDisplay,
    this.bonusLabel,
    required this.sortOrder,
  });

  factory CoinProduct.fromJson(Map<String, dynamic> json) {
    return CoinProduct(
      id: json['id'].toString(),
      productId: json['product_id'] as String,
      name: json['name'] as String,
      coinsAmount: json['coins_amount'] as int,
      priceDisplay: (json['price_display'] as String?) ?? '',
      bonusLabel: json['bonus_label'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [id, productId, name, coinsAmount, priceDisplay, bonusLabel, sortOrder];
}
