import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String id;
  final String email;
  final String username;
  final int coins;
  final int currentStreak;
  final DateTime? adFreeUntil;
  final bool hasNoAds;

  const User({
    required this.id,
    required this.email,
    required this.username,
    this.coins = 0,
    this.currentStreak = 0,
    this.adFreeUntil,
    this.hasNoAds = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final adFreeUntilRaw = json['ad_free_until'] as String?;
    final adFreeUntil = adFreeUntilRaw != null
        ? DateTime.parse(adFreeUntilRaw)
        : null;
    final hasNoAdsRaw = json['has_no_ads'] as bool?;

    return User(
      id: json['id'].toString(),
      email: json['email'] as String,
      username: json['username'] as String,
      coins: json['coins'] as int? ?? 0,
      currentStreak: json['current_streak'] as int? ?? 0,
      adFreeUntil: adFreeUntil,
      hasNoAds:
          hasNoAdsRaw ??
          (adFreeUntil != null && adFreeUntil.isAfter(DateTime.now().toUtc())),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'coins': coins,
      'current_streak': currentStreak,
      'ad_free_until': adFreeUntil?.toIso8601String(),
      'has_no_ads': hasNoAds,
    };
  }

  @override
  List<Object?> get props => [
    id,
    email,
    username,
    coins,
    currentStreak,
    adFreeUntil,
    hasNoAds,
  ];
}
