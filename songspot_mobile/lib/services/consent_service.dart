enum PrivacyOptionsResult { shown, notRequired, failed }

class ConsentService {
  ConsentService._();
  static final ConsentService _instance = ConsentService._();
  factory ConsentService() => _instance;

  Future<void> gatherConsent() async {}
  Future<PrivacyOptionsResult> showPrivacyOptionsForm() async =>
      PrivacyOptionsResult.notRequired;
}
