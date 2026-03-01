# AdMob + No-Ads Pass Setup

This guide documents the in-app ad monetization currently wired in SongSpot.

## What is implemented

1. Rewarded ad as daily-game retry unlock on last-snippet failure (`Watch Ad for Retry`).
2. Rewarded ad in Coin Shop (`Watch Ad`) to claim bonus coins.
3. Interstitial ad before showing daily-game results (once per room/day).
4. Banner ad on pack browsing (`PackListScreen`) only.
5. Coin-based `No Ads (30 days)` purchase from Settings.
6. Backend retry endpoint, reward claim endpoint, and ad-free pass endpoint.
7. GDPR/ads consent flow (UMP) at app startup + privacy options entry in Settings.

## File map

### Mobile (Flutter)

- Ad config: `songspot_mobile/lib/config/admob_config.dart`
- Ad runtime service: `songspot_mobile/lib/services/admob_service.dart`
- Consent runtime service (UMP): `songspot_mobile/lib/services/consent_service.dart`
- Game placements + retry CTA: `songspot_mobile/lib/screens/game/game_screen.dart`
- Coin Shop rewarded bonus CTA: `songspot_mobile/lib/screens/shop/coin_shop_screen.dart`
- Banner placement: `songspot_mobile/lib/screens/packs/pack_list_screen.dart`
- No-ads purchase UI: `songspot_mobile/lib/screens/settings/settings_screen.dart`
- API client hooks: `songspot_mobile/lib/services/api_service.dart`
- User model (`has_no_ads` / `ad_free_until`): `songspot_mobile/lib/models/user.dart`

### Backend (Django)

- User ad-free field: `songspot_backend/authentication/models.py` (`ad_free_until`)
- Reward audit model: `songspot_backend/authentication/models.py` (`AdRewardClaim`)
- Endpoints:
  - `POST /api/auth/no-ads/activate/`
  - `POST /api/auth/ads/reward/`
  - `GET /api/auth/ads/reward/status/`
  - `POST /api/game/rooms/<room_id>/daily-game/retry/`
- Views: `songspot_backend/authentication/views.py`
- URLs: `songspot_backend/authentication/urls.py`, `songspot_backend/game/urls.py`
- Migrations:
  - `0005_user_ad_free_until.py`
  - `0006_adrewardclaim.py`
  - `0023_dailygamesession_retry_fields.py`

## Flutter dependency

`songspot_mobile/pubspec.yaml` includes:

```yaml
google_mobile_ads: ^7.0.0
```

Run:

```bash
cd songspot_mobile
flutter pub get
```

## Platform app IDs

### Android

`songspot_mobile/android/app/src/main/AndroidManifest.xml` contains:

```xml
<meta-data
            android:name="com.google.android.gms.ads.APPLICATION_ID"
            android:value="ca-app-pub-3940256099942544~3347511713" />
```

### iOS

`songspot_mobile/ios/Runner/Info.plist` contains:

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-3940256099942544~1458002511</string>
```

Use Google test App IDs only for local testing. For production, each platform must use its own real AdMob App ID.

## Environment variables

`songspot_mobile/.env`:

```env
ADMOB_USE_TEST_IDS=true
ADMOB_CONSENT_DEBUG_EEA=false
ADMOB_CONSENT_TEST_DEVICE_IDS=

ADMOB_REWARDED_RETRY_AD_UNIT_ID_ANDROID=
ADMOB_REWARDED_RETRY_AD_UNIT_ID_IOS=
ADMOB_REWARDED_COIN_SHOP_AD_UNIT_ID_ANDROID=
ADMOB_REWARDED_COIN_SHOP_AD_UNIT_ID_IOS=
ADMOB_INTERSTITIAL_BEFORE_RESULTS_AD_UNIT_ID_ANDROID=
ADMOB_INTERSTITIAL_BEFORE_RESULTS_AD_UNIT_ID_IOS=
ADMOB_BANNER_PACK_LIST_AD_UNIT_ID_ANDROID=
ADMOB_BANNER_PACK_LIST_AD_UNIT_ID_IOS=
```

When `ADMOB_USE_TEST_IDS=true`, built-in Google test unit IDs are used.

`ADMOB_CONSENT_DEBUG_EEA=true` can be used in debug builds to force EEA and test GDPR consent form behavior.

## Backend monetization settings

`songspot_backend/songspot/settings.py`:

```python
NO_ADS_PASS_COINS = int(os.environ.get('NO_ADS_PASS_COINS', '700'))
NO_ADS_PASS_DAYS = int(os.environ.get('NO_ADS_PASS_DAYS', '30'))
AD_REWARD_COINS = int(os.environ.get('AD_REWARD_COINS', '10'))
AD_REWARD_DAILY_CAP = int(os.environ.get('AD_REWARD_DAILY_CAP', '2'))
DAILY_GAME_MAX_RETRIES = int(os.environ.get('DAILY_GAME_MAX_RETRIES', '2'))
DAILY_GAME_RETRY_COIN_COST = int(os.environ.get('DAILY_GAME_RETRY_COIN_COST', '120'))
```

## API behavior

### Activate no-ads pass

`POST /api/auth/no-ads/activate/`

Success:

```json
{
  "message": "Ad-free pass activated for 30 days",
  "coins": 1234,
  "cost_coins": 700,
  "duration_days": 30,
  "ad_free_until": "2026-03-28T12:34:56.000000+00:00",
  "has_no_ads": true
}
```

### Claim rewarded ad coins

`POST /api/auth/ads/reward/`

Body:

```json
{ "placement": "coin_shop_bonus" }
```

Success:

```json
{
  "message": "Reward credited",
  "coins": 950,
  "coins_awarded": 10,
  "daily_cap": 2,
  "remaining_today": 1
}
```

If cap reached: `429`.

### Rewarded ad status

`GET /api/auth/ads/reward/status/`

Success:

```json
{
  "reward_coins": 10,
  "daily_cap": 2,
  "claims_today": 1,
  "remaining_today": 1
}
```

### Unlock daily-game retry

`POST /api/game/rooms/<room_id>/daily-game/retry/`

Body:

```json
{ "action": "ad" }
```

or

```json
{ "action": "coins" }
```

or

```json
{ "action": "forfeit" }
```

## Notes

- Ads are skipped when user has active ad-free pass (`has_no_ads=true`).
- Retry order is enforced server-side: first ad, then coins.
- Keep Google test IDs during development/testing.

## How to create AdMob app and ad units

1. Open https://admob.google.com and sign in with your Google account.
2. Complete account setup (country/time zone/payment profile).
3. Click **Apps** -> **Add app**.
4. Add your Android app (package name) and iOS app (bundle ID).  
   If app is not yet in store, choose **No** and add manually.
5. For each app, create ad units:
   - Rewarded (retry unlock)
   - Rewarded (coin shop)
   - Interstitial (before result)
   - Banner (pack list)
6. Copy:
   - AdMob **App ID** for Android/iOS
   - Each ad unit ID
7. Paste IDs into:
   - Android App ID: `AndroidManifest.xml`
   - iOS App ID: `Info.plist`
   - Unit IDs: `songspot_mobile/.env`
8. For production builds, set `ADMOB_USE_TEST_IDS=false`.

## Regulation and consent setup (AdMob)

This section is an implementation checklist, not legal advice. You should still validate your final policy/legal text with counsel.

### 1. Understand where consent is required

- EEA + UK + Switzerland: follow Google EU User Consent Policy and gather valid consent for ads-related processing.
- Regulated US states: provide required privacy choices (US state regulations message).
- iOS IDFA/ATT: if you want tracking permission for personalized ads measurement, configure the IDFA message and ATT prompt flow.

Important policy milestone:
- Since January 16, 2024, Google requires a Google-certified CMP for EEA/UK traffic under the EU user consent policy flow.

### 2. Configure messages in AdMob UI

In AdMob, go to `Privacy & messaging` and configure all relevant message types.

#### A) European regulations message (EEA/UK/CH)

1. `Privacy & messaging` -> `European regulations` -> `Create` (or `Manage` -> `Create message`).
2. Select your apps.
3. Set default language + additional languages.
4. Configure user choices and message text.
5. Review ad partners list (especially if you use mediation).
6. Publish the message.

Notes:
- Keep a consent-revocation path available at all times (via privacy options entry point in-app).
- If you add new mediation partners later, re-check ad partners and republish if needed.

#### B) US state regulations message

1. `Privacy & messaging` -> `US state regulations` -> `Create` (or `Manage` -> `Create message`).
2. Select apps + languages.
3. Configure behavior and text.
4. Publish.

Note:
- For apps, this message is typically surfaced via your privacy options entry point.

#### C) iOS IDFA message (optional but recommended if you use ATT)

1. `Privacy & messaging` -> `IDFA explainer` -> `Create`.
2. Select iOS app(s).
3. Configure text + languages.
4. Publish.

If you enable this:
- Add `NSUserTrackingUsageDescription` to `songspot_mobile/ios/Runner/Info.plist`.
- Ensure ATT flow is correctly configured in your iOS app build.

Current repo status:
- `NSUserTrackingUsageDescription` is present in `Info.plist`.
- Review and finalize the wording to match your exact ATT and ad-use disclosures.

### 3. App-side requirements (SongSpot status)

Implemented in this repo:
- Consent info is refreshed at app start (`ConsentService.gatherConsent()`).
- Consent form is shown when required.
- Ads are only requested when consent allows (`AdMobService.canServeAds()`).
- Privacy options entry point exists (Settings screen -> `showPrivacyOptionsForm`).

Environment toggles for QA:
- `ADMOB_CONSENT_DEBUG_EEA=true` to force EEA consent flow in debug.
- `ADMOB_CONSENT_TEST_DEVICE_IDS=...` for deterministic UMP debug behavior.

### 4. Store and disclosure requirements

- Add and maintain a public privacy policy URL.
- In AdMob, ensure app privacy policy URL is filled for each app.
- Google Play: complete `Data safety` disclosures for ads/SDK data handling.
- Apple App Store: complete App Privacy nutrition labels.
- If using iOS ATT, make sure wording in `NSUserTrackingUsageDescription` matches your real usage.
- Set up `app-ads.txt` on your domain and register the domain consistently in Play/App Store.
- Repo support: SongSpot backend exposes `/app-ads.txt` from `APP_ADS_TXT` setting, and a root `app-ads.txt` file is included for deployment convenience.

### 5. Pre-release compliance QA checklist

Run this before each production release:

1. Fresh install in EEA test scenario: European regulations message appears before ad serving.
2. Privacy options entry point can reopen and update consent.
3. US state scenario: US message is accessible from privacy options entry point.
4. iOS ATT scenario (if enabled): IDFA explainer + ATT prompt sequence works.
5. Denied consent path: app remains functional and ads behavior degrades gracefully.
6. `ADMOB_USE_TEST_IDS=false` and all production IDs are present for both platforms.
7. AdMob dashboard has no consent-policy warning banners for your app.

### 6. Official references

- EU User Consent Policy: https://www.google.com/about/company/user-consent-policy.html
- AdMob UMP Get started (Android/iOS/Flutter): https://developers.google.com/admob/android/privacy
- GDPR IAB support (Flutter): https://developers.google.com/admob/flutter/privacy/gdpr
- US IAB support (Android guide): https://developers.google.com/admob/android/privacy/us-iab-support
- AdMob available user message types: https://support.google.com/admob/answer/10114020
- Create European regulations message (apps): https://support.google.com/admob/answer/10113207
- Create US state regulations message: https://support.google.com/admob/answer/10860309
- IDFA support (Flutter/iOS): https://developers.google.com/admob/flutter/privacy/idfa
- Play Data disclosure guide: https://developers.google.com/admob/android/privacy/play-data-disclosure
- App Store data disclosure guide: https://developers.google.com/admob/ios/privacy/data-disclosure
- app-ads.txt setup: https://developers.google.com/admob/ios/app-ads

## Production rollout checklist

Use this list before publishing a production build.

1. Create production AdMob assets

- In AdMob, create your real app entries (Android package name + iOS bundle ID).
- Create real ad units for each placement you use:
  - Rewarded (retry unlock)
  - Rewarded (coin shop bonus)
  - Interstitial (before results)
  - Banner (pack list)

2. Replace all test IDs in app config

- Android: replace test App ID in `songspot_mobile/android/app/src/main/AndroidManifest.xml`.
- iOS: replace test App ID in `songspot_mobile/ios/Runner/Info.plist`.
- Mobile env: in `songspot_mobile/.env`, set:
  - `ADMOB_USE_TEST_IDS=false`
  - real values for all placement-specific `ADMOB_*_AD_UNIT_ID_*` keys.

Important:
- `AdMobConfig` currently falls back to Google test unit IDs when env values are empty.
- Do not ship production with empty `ADMOB_*_AD_UNIT_ID_*` values.

3. Implement privacy + consent requirements

- Follow the full `Regulation and consent setup (AdMob)` section above.

4. Verify policy-safe ad behavior

- Keep ads on natural breaks (already your chosen strategy).
- Avoid interstitial surprises and avoid placing ads on purchase-critical UI.
- Use test ads/test devices during QA to avoid invalid traffic from internal testing.

5. Store/disclosure and inventory setup

- Configure app-ads.txt for your app domain and set the same domain in store listing.
- Complete Play Store / App Store privacy disclosures for ad usage.

6. Release and monitor

- Start with staged rollout (small percentage first).
- Monitor AdMob dashboards: match rate, RPM, crashes, and policy/invalid traffic alerts.
- Expect that new ad units/apps can take time before stable fill.

## Current repo gaps before production

- Confirm iOS and Android App IDs are platform-correct in `AndroidManifest.xml` and `Info.plist`.
- Confirm each placement ad unit ID in `.env` is platform-correct (Android vs iOS) before release.
- Finalize `NSUserTrackingUsageDescription` wording in `Info.plist` with final legal copy.
- UMP consent flow is implemented in Flutter; configure messages in AdMob Privacy & messaging and validate behavior on a test device.
