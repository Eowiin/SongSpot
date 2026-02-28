# AdMob + No-Ads Pass Setup

This guide documents the in-app ad monetization currently wired in SongSpot.

## What is implemented

1. Rewarded ad as daily-game retry unlock on last-snippet failure (`Watch Ad for Retry`).
2. Rewarded ad in Coin Shop (`Watch Ad`) to claim bonus coins.
3. Interstitial ad before showing daily-game results (once per room/day).
4. Banner ad on pack browsing (`PackListScreen`) only.
5. Coin-based `No Ads (30 days)` purchase from Settings.
6. Backend retry endpoint, reward claim endpoint, and ad-free pass endpoint.

## File map

### Mobile (Flutter)

- Ad config: `songspot_mobile/lib/config/admob_config.dart`
- Ad runtime service: `songspot_mobile/lib/services/admob_service.dart`
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

Both are Google test App IDs; replace with real ones for production.

## Environment variables

`songspot_mobile/.env`:

```env
ADMOB_USE_TEST_IDS=true

ADMOB_REWARDED_AD_UNIT_ID_ANDROID=
ADMOB_REWARDED_AD_UNIT_ID_IOS=
ADMOB_INTERSTITIAL_AD_UNIT_ID_ANDROID=
ADMOB_INTERSTITIAL_AD_UNIT_ID_IOS=
ADMOB_BANNER_AD_UNIT_ID_ANDROID=
ADMOB_BANNER_AD_UNIT_ID_IOS=
```

When `ADMOB_USE_TEST_IDS=true`, built-in Google test unit IDs are used.

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
  - real values for all `ADMOB_*_AD_UNIT_ID_*` keys.

Important:
- `AdMobConfig` currently falls back to Google test unit IDs when env values are empty.
- Do not ship production with empty `ADMOB_*_AD_UNIT_ID_*` values.

3. Implement privacy + consent requirements

- Add Google UMP consent flow at app startup and request consent info update each launch.
- Add a persistent privacy options entry point so users can change consent later.
- If you request tracking on iOS, add ATT prompt flow and `NSUserTrackingUsageDescription`.

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

- `AndroidManifest.xml` and `Info.plist` still contain Google test App IDs.
- `.env` still has `ADMOB_USE_TEST_IDS=true` in local example.
- No UMP consent flow is currently implemented in Flutter code.
