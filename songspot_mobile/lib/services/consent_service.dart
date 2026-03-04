import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/admob_config.dart';

enum PrivacyOptionsResult { shown, notRequired, failed }

class ConsentService {
  ConsentService._();
  static final ConsentService _instance = ConsentService._();
  factory ConsentService() => _instance;

  bool _consentFlowCompleted = false;
  bool _canRequestAds = false;
  PrivacyOptionsRequirementStatus _privacyOptionsStatus =
      PrivacyOptionsRequirementStatus.unknown;
  Future<void>? _gatherInFlight;

  bool get canRequestAds => _canRequestAds;
  bool get consentFlowCompleted => _consentFlowCompleted;
  bool get privacyOptionsRequired =>
      _privacyOptionsStatus == PrivacyOptionsRequirementStatus.required;

  Future<void> gatherConsent() async {
    if (_gatherInFlight != null) return _gatherInFlight!;

    final completer = Completer<void>();
    _gatherInFlight = completer.future;
    var finished = false;

    Future<void> finishFlow() async {
      if (finished) return;
      finished = true;
      await _refreshConsentState();
      _consentFlowCompleted = true;
      if (!completer.isCompleted) completer.complete();
      _gatherInFlight = null;
    }

    final params = ConsentRequestParameters(
      consentDebugSettings: _buildDebugSettings(),
    );

    // Safety net: if requestConsentInfoUpdate never calls either callback
    // (e.g. network timeout on older Android), don't hang forever.
    final timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (finished) return;
      try {
        ConsentInformation.instance.reset();
      } catch (_) {}
      unawaited(finishFlow());
    });

    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        timeoutTimer.cancel();
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
        } catch (_) {
        } finally {
          await finishFlow();
        }
      },
      (_) async {
        timeoutTimer.cancel();
        await finishFlow();
      },
    );

    return _gatherInFlight!;
  }

  Future<PrivacyOptionsResult> showPrivacyOptionsForm() async {
    if (!_consentFlowCompleted) {
      await gatherConsent();
    } else {
      await _refreshConsentState();
    }

    if (_privacyOptionsStatus != PrivacyOptionsRequirementStatus.required) {
      return PrivacyOptionsResult.notRequired;
    }

    try {
      FormError? formError;
      await ConsentForm.showPrivacyOptionsForm((error) {
        formError = error;
      });
      await _refreshConsentState();
      if (formError != null) {
        return PrivacyOptionsResult.failed;
      }
      return PrivacyOptionsResult.shown;
    } catch (_) {
      await _refreshConsentState();
      return PrivacyOptionsResult.failed;
    }
  }

  ConsentDebugSettings? _buildDebugSettings() {
    if (!kDebugMode) return null;

    final testDeviceIds = AdMobConfig.consentTestDeviceIds;
    final forceEea = AdMobConfig.consentDebugForceEea;

    if (!forceEea && testDeviceIds.isEmpty) {
      return null;
    }

    return ConsentDebugSettings(
      debugGeography: forceEea ? DebugGeography.debugGeographyEea : null,
      testIdentifiers: testDeviceIds.isEmpty ? null : testDeviceIds,
    );
  }

  Future<void> _refreshConsentState() async {
    try {
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
    } catch (_) {
      _canRequestAds = false;
    }

    try {
      _privacyOptionsStatus = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
    } catch (_) {
      _privacyOptionsStatus = PrivacyOptionsRequirementStatus.unknown;
    }
  }
}
