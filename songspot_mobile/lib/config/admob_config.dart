import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AdMobConfig {
  static String _read(String key, String fallback) {
    final value = dotenv.env[key]?.trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  static bool get useTestIds {
    final raw = dotenv.env['ADMOB_USE_TEST_IDS']?.toLowerCase();
    if (raw == 'true') return true;
    if (raw == 'false') return false;
    return !kReleaseMode;
  }

  static String get rewardedAdUnitId {
    if (useTestIds) {
      return Platform.isIOS
          ? 'ca-app-pub-3940256099942544/1712485313'
          : 'ca-app-pub-3940256099942544/5224354917';
    }
    return Platform.isIOS
        ? _read(
            'ADMOB_REWARDED_AD_UNIT_ID_IOS',
            'ca-app-pub-3940256099942544/1712485313',
          )
        : _read(
            'ADMOB_REWARDED_AD_UNIT_ID_ANDROID',
            'ca-app-pub-3940256099942544/5224354917',
          );
  }

  static String get interstitialAdUnitId {
    if (useTestIds) {
      return Platform.isIOS
          ? 'ca-app-pub-3940256099942544/4411468910'
          : 'ca-app-pub-3940256099942544/1033173712';
    }
    return Platform.isIOS
        ? _read(
            'ADMOB_INTERSTITIAL_AD_UNIT_ID_IOS',
            'ca-app-pub-3940256099942544/4411468910',
          )
        : _read(
            'ADMOB_INTERSTITIAL_AD_UNIT_ID_ANDROID',
            'ca-app-pub-3940256099942544/1033173712',
          );
  }

  static String get bannerAdUnitId {
    if (useTestIds) {
      return Platform.isIOS
          ? 'ca-app-pub-3940256099942544/2934735716'
          : 'ca-app-pub-3940256099942544/6300978111';
    }
    return Platform.isIOS
        ? _read(
            'ADMOB_BANNER_AD_UNIT_ID_IOS',
            'ca-app-pub-3940256099942544/2934735716',
          )
        : _read(
            'ADMOB_BANNER_AD_UNIT_ID_ANDROID',
            'ca-app-pub-3940256099942544/6300978111',
          );
  }
}
