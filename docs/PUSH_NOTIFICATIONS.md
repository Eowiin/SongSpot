# Push Notifications (FCM)

This project uses Firebase Cloud Messaging (FCM) for iOS and Android push.

## What is implemented

- Multi-device support per user via `authentication.UserDevicePushToken`.
- Device registration API:
  - `POST /api/auth/push/devices/register/`
  - `POST /api/auth/push/devices/unregister/`
- Push delivery via `authentication/services/push_service.py` on:
  - new `DailySong` creation
  - new `RoomMessage` creation (sender excluded, and only users who already guessed correctly for the active daily song)
- Per-device preferences:
  - `daily_song_enabled`
  - `messages_enabled`

## Backend configuration

### 1) Firebase server credentials (required for backend send)

Your Django backend sends notifications through Firebase Admin SDK.
You must provide a Firebase **Service Account JSON** (this is separate from APNs files).

Firebase Console path:
- Project Settings -> Service accounts -> Generate new private key (JSON)

Set one of:

```env
FCM_SERVICE_ACCOUNT_PATH=/absolute/path/to/firebase-service-account.json
```

or

```env
FCM_SERVICE_ACCOUNT_JSON={"type":"service_account", ...}
```

Do not commit service-account JSON files. The backend `.gitignore` excludes local files like `songspot_backend/firebase-service-account.json`.

If neither is set, push notifications are skipped safely.

### 2) Runtime services (required)

Push is sent inline by the Django process through `firebase_admin`, so the API
is the only service required. There is no broker and no worker.

## Mobile configuration

### Android

1. Add `songspot_mobile/android/app/google-services.json`.
2. Rebuild app after `flutter pub get`.
3. Keep this file local-only; it is gitignored.

### iOS

1. Add `songspot_mobile/ios/Runner/GoogleService-Info.plist` to the Runner target.
2. Enable **Push Notifications** and **Background Modes > Remote notifications** in Xcode.
3. In Firebase Console (Project Settings -> Cloud Messaging), configure APNs:
   - Recommended: APNs Authentication Key (`.p8`)
   - Alternative: APNs certificates (`.p12`)
4. Keep this file local-only; it is gitignored.

## APNs `.p8` vs `.p12`

- `.p8` (APNs Auth Key): recommended, modern setup, one key can cover environments.
- `.p12` (APNs certificate): legacy option, usually more operational overhead.

If you already generated a `.p8` on Apple Developer, that is the right file to use.
In Firebase, upload it under the APNs Authentication Key section (with Key ID + Team ID).

## Runtime requirements

- Django app running (HTTP + websocket via ASGI).
- Mobile app calls register/unregister automatically on login/logout.

## Local run commands (host machine)

From `songspot_backend` in your venv:

```bash
python manage.py runserver 0.0.0.0:8000
```

## Local run commands (Docker Compose)

From repo root:

```bash
export FCM_SERVICE_ACCOUNT_PATH=/absolute/path/to/firebase-service-account.json
docker compose up --build
```
