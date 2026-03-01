import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

enum RewardedPlacement { retryUnlock, coinShopBonus }

class AdMobConfig {
  static const String _iosRewardedTestId =
      'ca-app-pub-3940256099942544/1712485313';
  static const String _androidRewardedTestId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _iosInterstitialTestId =
      'ca-app-pub-3940256099942544/4411468910';
  static const String _androidInterstitialTestId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _iosBannerTestId =
      'ca-app-pub-3940256099942544/2934735716';
  static const String _androidBannerTestId =
      'ca-app-pub-3940256099942544/6300978111';

  static String _readFirst(List<String> keys, String fallback) {
    for (final key in keys) {
      final value = dotenv.env[key]?.trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return fallback;
  }

  static bool get useTestIds {
    final raw = dotenv.env['ADMOB_USE_TEST_IDS']?.toLowerCase();
    if (raw == 'true') return true;
    if (raw == 'false') return false;
    return !kReleaseMode;
  }

  static bool get consentDebugForceEea {
    final raw = dotenv.env['ADMOB_CONSENT_DEBUG_EEA']?.toLowerCase();
    return raw == 'true';
  }

  static List<String> get consentTestDeviceIds {
    final raw = dotenv.env['ADMOB_CONSENT_TEST_DEVICE_IDS']?.trim() ?? '';
    if (raw.isEmpty) return const [];
    return raw
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  static String rewardedAdUnitIdFor(RewardedPlacement placement) {
    if (useTestIds) {
      return Platform.isIOS ? _iosRewardedTestId : _androidRewardedTestId;
    }
    if (placement == RewardedPlacement.retryUnlock) {
      return Platform.isIOS
          ? _readFirst(const [
              'ADMOB_REWARDED_RETRY_AD_UNIT_ID_IOS',
              'ADMOB_REWARDED_AD_UNIT_ID_IOS',
            ], _iosRewardedTestId)
          : _readFirst(const [
              'ADMOB_REWARDED_RETRY_AD_UNIT_ID_ANDROID',
              'ADMOB_REWARDED_AD_UNIT_ID_ANDROID',
            ], _androidRewardedTestId);
    }
    return Platform.isIOS
        ? _readFirst(const [
            'ADMOB_REWARDED_COIN_SHOP_AD_UNIT_ID_IOS',
            'ADMOB_REWARDED_AD_UNIT_ID_IOS',
          ], _iosRewardedTestId)
        : _readFirst(const [
            'ADMOB_REWARDED_COIN_SHOP_AD_UNIT_ID_ANDROID',
            'ADMOB_REWARDED_AD_UNIT_ID_ANDROID',
          ], _androidRewardedTestId);
  }

  static String get interstitialBeforeResultsAdUnitId {
    if (useTestIds) {
      return Platform.isIOS
          ? _iosInterstitialTestId
          : _androidInterstitialTestId;
    }
    return Platform.isIOS
        ? _readFirst(const [
            'ADMOB_INTERSTITIAL_BEFORE_RESULTS_AD_UNIT_ID_IOS',
            'ADMOB_INTERSTITIAL_AD_UNIT_ID_IOS',
          ], _iosInterstitialTestId)
        : _readFirst(const [
            'ADMOB_INTERSTITIAL_BEFORE_RESULTS_AD_UNIT_ID_ANDROID',
            'ADMOB_INTERSTITIAL_AD_UNIT_ID_ANDROID',
          ], _androidInterstitialTestId);
  }

  static String get bannerPackListAdUnitId {
    if (useTestIds) {
      return Platform.isIOS ? _iosBannerTestId : _androidBannerTestId;
    }
    return Platform.isIOS
        ? _readFirst(const [
            'ADMOB_BANNER_PACK_LIST_AD_UNIT_ID_IOS',
            'ADMOB_BANNER_AD_UNIT_ID_IOS',
          ], _iosBannerTestId)
        : _readFirst(const [
            'ADMOB_BANNER_PACK_LIST_AD_UNIT_ID_ANDROID',
            'ADMOB_BANNER_AD_UNIT_ID_ANDROID',
          ], _androidBannerTestId);
  }

  static String get rewardedAdUnitId =>
      rewardedAdUnitIdFor(RewardedPlacement.retryUnlock);

  static String get interstitialAdUnitId => interstitialBeforeResultsAdUnitId;

  static String get bannerAdUnitId => bannerPackListAdUnitId;
}
