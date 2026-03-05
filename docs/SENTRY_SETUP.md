# Sentry Error Monitoring Setup

Sentry is already integrated in the codebase. This guide covers what you need to do on sentry.io and how to connect it.

---

## 1. Create Sentry Account & Projects

1. Go to [sentry.io](https://sentry.io) and create a free account
2. Create an organization (e.g., "songspot")
3. Create **two projects**:
   - **songspot-backend** → Platform: `Django`
   - **songspot-mobile** → Platform: `Flutter`
4. Copy the **DSN** (Data Source Name) for each project — you'll need both

---

## 2. Backend Configuration

The Sentry SDK is already integrated in `settings.py`. You just need to set the environment variable.

Add to your production `.env`:
```env
SENTRY_DSN=https://your-key@sentry.io/project-id   # from songspot-backend project
SENTRY_ENVIRONMENT=production
APP_VERSION=1.0.0
```

Sentry only activates when `DEBUG=False` **and** `SENTRY_DSN` is set. It does nothing in local dev.

### Test it (on the server)

```bash
cd /var/www/songspot/songspot_backend
source .venv/bin/activate
python manage.py shell

>>> import sentry_sdk
>>> sentry_sdk.capture_message("Sentry backend is working!")
```

Then check your Sentry dashboard — the message should appear within seconds.

---

## 3. Mobile Configuration

The SDK is already integrated in `main.dart`. The DSN is injected at **build time** via `--dart-define`, not from `.env`.

### Configure DSN for Fastlane builds

The Fastlane lanes already pass `--dart-define=SENTRY_DSN` automatically. You just need to set the value in each platform's `fastlane/.env`:

**`android/fastlane/.env`**
```env
SENTRY_DSN="https://your-key@sentry.io/project-id"
SENTRY_ENVIRONMENT="production"
```

**`ios/fastlane/.env`**
```env
SENTRY_DSN="https://your-key@sentry.io/project-id"
SENTRY_ENVIRONMENT="production"
```

Then run your normal Fastlane lanes — no extra steps needed:

```bash
# Android (builds .aab)
cd android && bundle exec fastlane internal

# iOS
cd ios && bundle exec fastlane testflight
```

If `SENTRY_DSN` is empty or not set, Sentry silently does nothing — the app works normally.

Errors are **never sent in debug mode** (`flutter run`) — only release builds report to Sentry.

---

## 4. Alert Configuration (Sentry Dashboard)

Set up alerts so you're notified automatically:

1. Go to **Alerts** in your Sentry project
2. Create rules for:
   - **First occurrence** of a new issue → email immediately
   - **High frequency** (e.g., > 10 occurrences in 1 hour) → email
3. Do this for **both** projects (backend + mobile)

---

## 5. Source Maps for Flutter (Optional)

Better stack traces for obfuscated release builds:

```bash
# Upload debug symbols after building
sentry-cli upload-dif \
  --org your-org \
  --project songspot-mobile \
  ./build/app/outputs/
```

Django does not need source maps — Python stack traces are already readable.

---

## Quick Checklist

- [ ] Create Sentry account and organization
- [ ] Create `songspot-backend` project (Django) → copy DSN
- [ ] Create `songspot-mobile` project (Flutter) → copy DSN
- [ ] Add `SENTRY_DSN` + `SENTRY_ENVIRONMENT` + `APP_VERSION` to server `.env`
- [ ] Test backend with `capture_message` in Django shell
- [ ] Pass `--dart-define=SENTRY_DSN=...` in mobile release builds
- [ ] Set up alert rules in Sentry dashboard (both projects)
