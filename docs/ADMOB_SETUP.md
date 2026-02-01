# AdMob + Daily Retry Setup

This guide explains how to set up the AdMob rewarded ad flow and the daily retry logic.

## Overview

Daily challenge retries work like this:

- The user gets 6 snippets.
- If they fail after snippet 6, the answer is not shown yet.
- Retry 1 requires watching a rewarded ad.
- Retry 2 requires spending 25 coins.
- If they fail again, the answer is revealed and the game is completed.

The backend enforces the retry requirements. The mobile app displays the prompt and triggers the ad or coin flow.

## Backend (Django)

No migrations are required for retries.

Changes are already in:

- `songspot_backend/game/views.py`
- `songspot_backend/game/serializers.py`

API behavior:

- When snippet 6 is failed, the response includes:
  - `retry_available`
  - `retries_used`
  - `retries_remaining`
  - `next_retry_requirement` (`ad` or `coins`)
  - `retry_cost_coins` (only for the coin retry)
- The next guess must include `retry_action`:
  - `retry_action: "ad"` for the first retry
  - `retry_action: "coins"` for the second retry

Example response after failing snippet 6:

```json
{
  "is_correct": false,
  "current_snippet": 6,
  "message": "No more snippets. You can retry.",
  "retry_available": true,
  "retries_used": 0,
  "retries_remaining": 2,
  "next_retry_requirement": "ad",
  "retry_cost_coins": null
}
```

Example retry request:

```json
{
  "track_id": "<track-uuid>",
  "retry_action": "ad"
}
```

## Mobile (Flutter)

### Dependencies

`songspot_mobile/pubspec.yaml` includes:

```
google_mobile_ads: ^7.0.0
```

Run:

```
flutter pub get
```

### SDK initialization

`songspot_mobile/lib/main.dart` initializes the Mobile Ads SDK:

```
await MobileAds.instance.initialize();
```

### Rewarded ads

Rewarded ad logic lives in:

- `songspot_mobile/lib/services/admob_service.dart`
- `songspot_mobile/lib/config/admob_config.dart`

`GameScreen` preloads and shows the rewarded ad when `next_retry_requirement == "ad"`.

## AdMob configuration

### Android App ID

`songspot_mobile/android/app/src/main/AndroidManifest.xml`:

```
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-3940256099942544~3347511713" />
```

Replace with your real Android App ID for production.

### iOS App ID

`songspot_mobile/ios/Runner/Info.plist`:

```
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-3940256099942544~1458002511</string>
```

Replace with your real iOS App ID for production.

### Rewarded Ad Unit IDs

`songspot_mobile/.env`:

```
ADMOB_REWARDED_AD_UNIT_ID_ANDROID=ca-app-pub-3940256099942544/5224354917
ADMOB_REWARDED_AD_UNIT_ID_IOS=ca-app-pub-3940256099942544/1712485313
```

These are Google test IDs. Replace with your real rewarded unit IDs before release.

## iOS pods

If this is the first time using `google_mobile_ads`:

```
cd ios
pod install
```

## Quick checklist

- [ ] Backend deployed with retry logic
- [ ] `flutter pub get`
- [ ] Android App ID updated
- [ ] iOS App ID updated
- [ ] Rewarded unit IDs updated in `.env`
- [ ] Test on device with test IDs
- [ ] Swap to production IDs before release
