import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/admob_config.dart';
import 'consent_service.dart';

class AdMobService {
  AdMobService._();
  static final AdMobService _instance = AdMobService._();
  factory AdMobService() => _instance;

  bool _initialized = false;
  final Set<RewardedPlacement> _loadingRewarded = <RewardedPlacement>{};
  final Map<RewardedPlacement, Completer<void>> _rewardedLoadCompleters = {};
  bool _loadingInterstitial = false;
  final Map<RewardedPlacement, RewardedAd> _rewardedAds = {};
  InterstitialAd? _interstitialAd;

  bool canServeAds({required bool adsDisabled}) {
    if (adsDisabled) return false;
    return ConsentService().canRequestAds;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    await ConsentService().gatherConsent();
    if (!ConsentService().canRequestAds) {
      debugPrint('AdMob initialization skipped: consent not available yet.');
      return;
    }
    await MobileAds.instance.initialize();
    _initialized = true;
  }

  Future<void> preloadRewarded({
    required bool adsDisabled,
    required RewardedPlacement placement,
  }) async {
    if (!canServeAds(adsDisabled: adsDisabled)) return;
    await initialize();
    if (!_initialized) return;
    if (_rewardedAds[placement] != null) {
      return;
    }

    final existingLoad = _rewardedLoadCompleters[placement];
    if (existingLoad != null) {
      await _awaitRewardedLoad(placement, existingLoad);
      return;
    }

    final loadCompleter = Completer<void>();
    _rewardedLoadCompleters[placement] = loadCompleter;
    _loadingRewarded.add(placement);
    RewardedAd.load(
      adUnitId: AdMobConfig.rewardedAdUnitIdFor(placement),
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingRewarded.remove(placement);
          _rewardedAds[placement] = ad;
          final completer = _rewardedLoadCompleters.remove(placement);
          if (completer != null && !completer.isCompleted) {
            completer.complete();
          }
        },
        onAdFailedToLoad: (error) {
          _loadingRewarded.remove(placement);
          debugPrint('AdMob rewarded load failed: $error');
          final completer = _rewardedLoadCompleters.remove(placement);
          if (completer != null && !completer.isCompleted) {
            completer.complete();
          }
        },
      ),
    );

    await _awaitRewardedLoad(placement, loadCompleter);
  }

  Future<bool> showRewarded({
    required bool adsDisabled,
    required RewardedPlacement placement,
    required Future<void> Function() onRewardEarned,
  }) async {
    if (!canServeAds(adsDisabled: adsDisabled)) return false;
    await initialize();
    if (!_initialized) return false;

    var ad = _rewardedAds.remove(placement);
    if (ad == null) {
      await preloadRewarded(adsDisabled: adsDisabled, placement: placement);
      ad = _rewardedAds.remove(placement);
      if (ad == null) return false;
    }

    var rewardGranted = false;
    var showFailed = false;
    final dismissCompleter = Completer<void>();
    final rewardSignalCompleter = Completer<void>();
    final rewardCompleter = Completer<void>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!dismissCompleter.isCompleted) dismissCompleter.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        showFailed = true;
        ad.dispose();
        if (!dismissCompleter.isCompleted) dismissCompleter.complete();
      },
    );

    try {
      await ad.show(
        onUserEarnedReward: (adWithoutView, rewardItem) {
          if (rewardGranted) return;
          rewardGranted = true;
          if (!rewardSignalCompleter.isCompleted) {
            rewardSignalCompleter.complete();
          }
          onRewardEarned()
              .then((_) {
                if (!rewardCompleter.isCompleted) rewardCompleter.complete();
              })
              .catchError((error, stackTrace) {
                if (!rewardCompleter.isCompleted) {
                  rewardCompleter.completeError(error, stackTrace);
                }
              });
        },
      );
    } catch (error) {
      showFailed = true;
      debugPrint('AdMob rewarded show failed: $error');
      ad.dispose();
      if (!dismissCompleter.isCompleted) dismissCompleter.complete();
    }

    await dismissCompleter.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
    if (!rewardGranted && !showFailed) {
      await rewardSignalCompleter.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
    }
    if (rewardGranted) {
      await rewardCompleter.future;
    }
    unawaited(preloadRewarded(adsDisabled: adsDisabled, placement: placement));
    return rewardGranted;
  }

  Future<void> preloadInterstitial({required bool adsDisabled}) async {
    if (!canServeAds(adsDisabled: adsDisabled)) return;
    await initialize();
    if (!_initialized) return;
    if (_interstitialAd != null || _loadingInterstitial) return;
    await _loadInterstitial();
  }

  Future<bool> tryShowInterstitialForRoomCompletion({
    required bool adsDisabled,
    required String roomId,
    required String gameDate,
    String completionScope = 'daily',
  }) async {
    if (!canServeAds(adsDisabled: adsDisabled)) return false;
    await initialize();
    if (!_initialized) return false;
    final prefs = await SharedPreferences.getInstance();
    final shownKey = _completionInterstitialShownKey(
      completionScope: completionScope,
      roomId: roomId,
      gameDate: gameDate,
    );
    if (prefs.getBool(shownKey) ?? false) return false;

    final ad = _interstitialAd ?? await _loadInterstitial();
    if (ad == null) return false;

    _interstitialAd = null;
    final completer = Completer<void>();
    var adActuallyShown = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        adActuallyShown = true;
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete();
      },
    );

    await ad.show();
    await completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {},
    );
    if (adActuallyShown) {
      await prefs.setBool(shownKey, true);
    }
    unawaited(preloadInterstitial(adsDisabled: adsDisabled));
    return adActuallyShown;
  }

  Future<InterstitialAd?> _loadInterstitial() async {
    if (_interstitialAd != null) return _interstitialAd;
    if (_loadingInterstitial) return null;

    _loadingInterstitial = true;
    final completer = Completer<InterstitialAd?>();

    InterstitialAd.load(
      adUnitId: AdMobConfig.interstitialBeforeResultsAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingInterstitial = false;
          _interstitialAd = ad;
          if (!completer.isCompleted) completer.complete(ad);
        },
        onAdFailedToLoad: (error) {
          _loadingInterstitial = false;
          debugPrint('AdMob interstitial load failed: $error');
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    );

    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => null,
    );
  }

  String _completionInterstitialShownKey({
    required String completionScope,
    required String roomId,
    required String gameDate,
  }) {
    return 'ads_interstitial_room_completion_${completionScope}_${roomId}_$gameDate';
  }

  Future<void> _awaitRewardedLoad(
    RewardedPlacement placement,
    Completer<void> loadCompleter,
  ) async {
    await loadCompleter.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        if (identical(_rewardedLoadCompleters[placement], loadCompleter)) {
          _rewardedLoadCompleters.remove(placement);
          _loadingRewarded.remove(placement);
        }
      },
    );
  }
}
