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

    final params = ConsentRequestParameters(
      consentDebugSettings: _buildDebugSettings(),
    );

    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        try {
          FormError? loadAndShowError;
          await ConsentForm.loadAndShowConsentFormIfRequired((formError) {
            loadAndShowError = formError;
          });
          if (loadAndShowError != null) {
            debugPrint(
              'Consent form load/show failed: ${loadAndShowError!.message}',
            );
          }
        } catch (e) {
          debugPrint('Consent form flow threw: $e');
        } finally {
          await _refreshConsentState();
          _consentFlowCompleted = true;
          if (!completer.isCompleted) completer.complete();
          _gatherInFlight = null;
        }
      },
      (formError) async {
        debugPrint('Consent info update failed: ${formError.message}');
        await _refreshConsentState();
        _consentFlowCompleted = true;
        if (!completer.isCompleted) completer.complete();
        _gatherInFlight = null;
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
        debugPrint('Privacy options form failed: ${formError!.message}');
        return PrivacyOptionsResult.failed;
      }
      return PrivacyOptionsResult.shown;
    } catch (e) {
      debugPrint('Privacy options form threw: $e');
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
