# In-App Purchases — Complete Guide

## Architecture overview

```
Flutter app (in_app_purchase)
  ↓  user taps Buy
Apple / Google store dialog
  ↓  payment confirmed
IAPService._verifyAndCreditPurchase()
  ↓  POST /api/auth/iap/verify/
Django backend (iap_views.py + iap_service.py)
  ↓  verify receipt with Apple/Google
Credit coins → return new balance
```

**Key files:**
| Layer | File |
|---|---|
| Flutter IAP service | `songspot_mobile/lib/services/iap_service.dart` |
| Flutter shop UI | `songspot_mobile/lib/screens/shop/coin_shop_screen.dart` |
| Flutter shop provider | `songspot_mobile/lib/providers/coin_shop_provider.dart` |
| Django verify endpoint | `songspot_backend/authentication/iap_views.py` |
| Django receipt logic | `songspot_backend/authentication/iap_service.py` |
| Django models | `songspot_backend/authentication/models.py` → `CoinProduct`, `IAPReceipt` |

**Product IDs** (must match exactly in both store consoles and Flutter code):
```
com.songspot.coins.500    → 500 coins   ($1.99)
com.songspot.coins.1200   → 1 200 coins  ($3.99)
com.songspot.coins.3000   → 3 000 coins  ($7.99)
com.songspot.coins.7000   → 7 000 coins  ($14.99)
```

---

## 1. Creating products in the stores

### App Store Connect (iOS)

**Prerequisites:**
- Apple Developer account ($99/year)
- App record created in App Store Connect
- **Paid Apps Agreement signed** (Agreements, Tax, and Banking → sign the Paid Apps contract)
  — without this, IAP products cannot go live

**Steps:**
1. App Store Connect → your app → **Monetization → In-App Purchases**
2. Click **+** → **Consumable** (coins are consumed each purchase, not a subscription)
3. For each product:
   - **Reference Name**: `SongSpot - Starter Pack 500`
   - **Product ID**: `com.songspot.coins.500` (exact match required)
   - **Price**: choose from Apple's price tiers ($1.99 = Tier 1, $3.99 = Tier 3, etc.)
   - **Localizations**: add English (and French if wanted) — name + description
4. **Status must be "Ready to Submit"** before it shows up in sandbox
5. Repeat for all 4 products

> You can do this before your first TestFlight build — no build upload required.

---

### Google Play Console (Android)

**Prerequisites:**
- Google Play Developer account ($25 one-time)
- Merchant account linked (Payments profile)
- **At least one APK/AAB uploaded to any track** (even internal) before products can be created

**Steps:**
1. Play Console → your app → **Monetization → Products → In-app products**
2. Click **Create product**
3. For each product:
   - **Product ID**: `com.songspot.coins.500`
   - **Name** and **Description**
   - **Price**: set in your currency (Play converts automatically)
   - **Status**: set to **Active**
4. Repeat for all 4 products

> Upload a signed AAB to Internal Testing first if the menu is greyed out.
> The BILLING permission in AndroidManifest.xml is already added.

---

## 2. Testing IAP

### iOS — Real device (recommended)

This is the **simplest and most reliable** approach.

**Setup (one-time):**
1. App Store Connect → **Users and Access → Sandbox → Testers**
2. Create a sandbox tester (use a fake email, doesn't need to be a real Apple ID)
3. On your **iPhone** (real device required, not simulator):
   - **iOS 16+**: Settings → Developer → Sandbox Account → sign in with sandbox tester
   - **Older iOS**: Settings → App Store → sign out of your real account → sign in with sandbox account

**Run the app:**
```bash
flutter run   # debug mode works fine on real device
```
Purchases go through Apple's sandbox — **no real charge**. The payment sheet shows `[Environment: Sandbox]`.

---

### iOS — Simulator (StoreKit Configuration)

The simulator has no App Store, so you need a local StoreKit config file.

**Setup (one-time in Xcode):**
1. Xcode → File → New → File → **StoreKit Configuration File** → save as `StoreKit.storekit` inside `ios/`
2. Add each product manually (product ID, price, type = Consumable)
3. Edit Scheme → **Options tab** → StoreKit Configuration → select `StoreKit.storekit`

**Run:**
```bash
flutter run   # purchases use the local config, no network needed
```

> Limitation: the local StoreKit config doesn't send a real receipt to your backend. You'll need to handle this in testing (sandbox mode on the backend already accepts everything, so it still works end-to-end).

---

### Android — Internal Testing track (recommended)

**Debug builds (`flutter run`) do NOT work** with Google Play Billing — the billing library requires a release-signed build.

**Setup (one-time):**
1. Play Console → **Setup → License testing**
2. Add your Gmail address(es)
3. Build and upload a release build:
   ```bash
   flutter build appbundle --release
   # Upload to Internal Testing in Play Console
   ```
4. Share the **Internal Testing opt-in link** with yourself
5. Install the app from Play Store using that link (not sideloaded)

**Test:**
- Open the installed app, tap Buy → the payment sheet shows **"Test card, always approves"**
- No real charge. The purchase is reflected in your backend as a real transaction.

> You must install from the Play Store link. Sideloading the APK may not connect to Play Billing correctly.

---

### Android — Physical device shortcut

If you want to avoid uploading every time, you can sideload a **release-signed APK** and it will work for license testers:

```bash
flutter build apk --release
adb install build/app/outputs/flutter-apk/app-release.apk
```

Requirements:
- Your Google account on the device must be a **license tester** (set up in Play Console)
- The APK must be signed with your **release keystore** (same key as Play Store)
- Package name must match (`com.songspot.app`)

---

## 3. Backend sandbox mode

The backend (`iap_service.py`) has a sandbox mode toggle in `settings.py`:

```python
IAP_SANDBOX_MODE = os.environ.get('IAP_SANDBOX_MODE', 'True') == 'True'
```

- **`True` (default)**: accepts ALL receipts without verifying with Apple/Google — safe for development and sandbox testing
- **`False`**: calls real Apple/Google APIs to verify — required for production

In your `.env` (or server environment):
```
IAP_SANDBOX_MODE=True    # development / testing
IAP_SANDBOX_MODE=False   # production
```

---

## 4. Verifying it works end-to-end (checklist)

Before going to production, run through this checklist:

### iOS sandbox checklist
- [ ] Products show up in the Coin Shop screen (not "Store not available")
- [ ] Tapping Buy shows the Apple payment sheet with `[Environment: Sandbox]`
- [ ] After confirming, coins are added to the balance (check the snackbar)
- [ ] The `IAPReceipt` record is created in Django admin with `status=verified`
- [ ] Tapping Buy again for the same transaction is rejected (idempotency check)
- [ ] App killed mid-purchase → reopen app → purchase is recovered and credited

### Android checklist
- [ ] Products show up in the Coin Shop screen
- [ ] Tapping Buy shows the Google Play payment sheet with test card
- [ ] After confirming, coins are added to the balance
- [ ] The `IAPReceipt` record is created in Django admin with `status=verified`
- [ ] Duplicate transaction ID is rejected

### Backend checks (Django admin)
- Go to `/admin/authentication/iapreceipt/` to see all purchase records
- Go to `/admin/authentication/cointransaction/` to see coin credits
- Go to `/admin/authentication/coinproduct/` to manage coin products

---

## 5. Going to production

### Step 1 — Implement real receipt verification

Replace the sandbox stubs in `songspot_backend/authentication/iap_service.py`.

**Apple (App Store Server API v2):**
1. App Store Connect → **Users and Access → Integrations → App Store Connect API**
2. Create an API key → download the `.p8` file
3. Note the Key ID and Issuer ID
4. Install `PyJWT` and `cryptography` on the backend:
   ```bash
   pip install PyJWT cryptography
   ```
5. Implement `verify_apple_receipt()`:
   ```python
   import jwt, time, requests

   def verify_apple_receipt(transaction_id, receipt_data):
       # Generate JWT for App Store Server API
       token = jwt.encode({
           'iss': settings.ASC_ISSUER_ID,
           'iat': int(time.time()),
           'exp': int(time.time()) + 1200,
           'aud': 'appstoreconnect-v1',
           'bid': 'com.songspot.app',
       }, settings.ASC_PRIVATE_KEY, algorithm='ES256',
          headers={'kid': settings.ASC_KEY_ID})

       # Try production first, fall back to sandbox (for TestFlight)
       for base_url in [
           'https://api.storekit.itunes.apple.com',
           'https://api.storekit-sandbox.itunes.apple.com',
       ]:
           r = requests.get(
               f'{base_url}/inApps/v1/transactions/{transaction_id}',
               headers={'Authorization': f'Bearer {token}'},
               timeout=10,
           )
           if r.status_code == 200:
               return {'valid': True}
           if r.status_code != 404:
               break

       return {'valid': False, 'error': f'Apple verification failed: {r.status_code}'}
   ```
6. Add to your `.env`:
   ```
   ASC_KEY_ID=URSCCVCYY9
   ASC_ISSUER_ID=e74e29e2-...
   ASC_PRIVATE_KEY=<contents of .p8 file>
   ```

**Google (Play Developer API):**
1. Google Cloud Console → your project → IAM → Create Service Account
2. Grant it the role: **Android Publisher API** (or Pub/Sub Publisher)
3. Download JSON key file
4. Play Console → Setup → API access → link the service account → grant **Financial data, orders, and cancellation survey responses** permission
5. Install client library:
   ```bash
   pip install google-api-python-client google-auth
   ```
6. Implement `verify_google_receipt()`:
   ```python
   from google.oauth2 import service_account
   from googleapiclient.discovery import build

   def verify_google_receipt(transaction_id, receipt_data, product_id):
       creds = service_account.Credentials.from_service_account_file(
           settings.GOOGLE_PLAY_KEY_FILE,
           scopes=['https://www.googleapis.com/auth/androidpublisher'],
       )
       service = build('androidpublisher', 'v3', credentials=creds)
       result = service.purchases().products().get(
           packageName='com.songspot.app',
           productId=product_id,
           token=receipt_data,
       ).execute()

       # purchaseState: 0 = Purchased, 1 = Cancelled, 2 = Pending
       if result.get('purchaseState') == 0:
           return {'valid': True}
       return {'valid': False, 'error': f"purchaseState={result.get('purchaseState')}"}
   ```
7. Add to your `.env`:
   ```
   GOOGLE_PLAY_KEY_FILE=/path/to/google-play-key.json
   ```

### Step 2 — Flip the switch
```
IAP_SANDBOX_MODE=False
```
Deploy the backend. The Flutter app code doesn't change at all.

### Step 3 — Submit for review

**iOS:**
- Each IAP product must be approved by Apple when you submit the app version
- The first time you submit IAP, Apple may ask for a screenshot of the paywall
- Make sure all 4 products are in "Ready to Submit" status before submission

**Android:**
- No separate review for IAP products — they go live when activated
- Your app still needs to pass the standard review

---

## 6. Backend deployment checklist

When deploying the backend (handled automatically by `scripts/deploy_backend.sh`):

```bash
python manage.py migrate          # creates CoinProduct / IAPReceipt tables
python manage.py seed_coin_products  # creates/updates the 4 coin products (idempotent)
```

`seed_coin_products` is **idempotent** — safe to run on every deploy. It uses `update_or_create` so it will never duplicate records. If you change a product name or bonus label, just edit `authentication/management/commands/seed_coin_products.py`, commit, and the next deploy will update the records automatically.

If you need to reset everything:
```bash
python manage.py seed_coin_products --clear   # deletes all, then re-creates
```

---

## 7. Useful commands

```bash
# Check IAP receipts in Django admin
open http://localhost:8000/admin/authentication/iapreceipt/

# Check coin products
open http://localhost:8000/admin/authentication/coinproduct/

# iOS real device (sandbox)
flutter run -d <device-id>

# Android release build (sideload for license testing)
flutter build apk --release
adb install build/app/outputs/flutter-apk/app-release.apk

# Android AAB (for Play Console)
flutter build appbundle --release
```
