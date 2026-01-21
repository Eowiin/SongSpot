# Sentry Error Monitoring Setup

Guide for adding Sentry error tracking to SongSpot (backend + mobile).

---

## 1. Create Sentry Account & Projects

1. Go to [sentry.io](https://sentry.io) and create an account
2. Create an organization (e.g., "songspot")
3. Create two projects:
   - **songspot-backend** (Platform: Django)
   - **songspot-mobile** (Platform: Flutter)
4. Copy the DSN (Data Source Name) for each project

---

## 2. Backend Setup (Django)

### Install Package

```bash
pip install sentry-sdk[django]
```

Add to `requirements.txt`:
```
sentry-sdk[django]>=1.39.0
```

### Configure in settings.py

```python
import sentry_sdk
from sentry_sdk.integrations.django import DjangoIntegration

# Only enable Sentry in production
if not DEBUG:
    sentry_sdk.init(
        dsn=os.environ.get('SENTRY_DSN'),
        integrations=[
            DjangoIntegration(
                transaction_style='url',
                middleware_spans=True,
            ),
        ],
        # Set traces_sample_rate to 1.0 to capture 100% of transactions
        # Lower this in production for high-traffic apps
        traces_sample_rate=0.1,  # 10% of requests
        # Set profiles_sample_rate to profile transactions
        profiles_sample_rate=0.1,
        # Send user info (id, email) with errors
        send_default_pii=True,
        # Environment tag
        environment=os.environ.get('SENTRY_ENVIRONMENT', 'production'),
        # Release version
        release=os.environ.get('APP_VERSION', '1.0.0'),
    )
```

### Add to .env

```env
SENTRY_DSN=https://your-key@sentry.io/project-id
SENTRY_ENVIRONMENT=production
APP_VERSION=1.0.0
```

### Test Integration

```python
# In Django shell or a test view
from sentry_sdk import capture_message, capture_exception

# Test message
capture_message("Sentry is working!")

# Test exception
try:
    1 / 0
except Exception as e:
    capture_exception(e)
```

---

## 3. Mobile Setup (Flutter)

### Install Package

Add to `pubspec.yaml`:
```yaml
dependencies:
  sentry_flutter: ^8.0.0
```

### Initialize in main.dart

```dart
import 'package:sentry_flutter/sentry_flutter.dart';

Future<void> main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment(
        'SENTRY_DSN',
        defaultValue: '', // Empty in dev, set in production build
      );
      options.environment = const String.fromEnvironment(
        'SENTRY_ENVIRONMENT',
        defaultValue: 'development',
      );
      // Performance monitoring
      options.tracesSampleRate = 0.1;
      // Only send in release mode
      options.beforeSend = (event, hint) {
        if (kDebugMode) return null; // Don't send in debug
        return event;
      };
    },
    appRunner: () => runApp(const MyApp()),
  );
}
```

### Wrap Your App

```dart
// In main.dart, wrap the root widget
runApp(
  SentryWidget(
    child: const MyApp(),
  ),
);
```

### Capture Errors Manually

```dart
import 'package:sentry_flutter/sentry_flutter.dart';

// Capture exception
try {
  // risky code
} catch (exception, stackTrace) {
  await Sentry.captureException(
    exception,
    stackTrace: stackTrace,
  );
}

// Capture message
await Sentry.captureMessage('Something happened');

// Add breadcrumb for context
Sentry.addBreadcrumb(Breadcrumb(
  message: 'User joined room',
  category: 'navigation',
  data: {'room_id': roomId},
));
```

### Build with DSN

```bash
# For release builds, pass the DSN
flutter build apk --dart-define=SENTRY_DSN=https://your-key@sentry.io/project-id --dart-define=SENTRY_ENVIRONMENT=production

flutter build ios --dart-define=SENTRY_DSN=https://your-key@sentry.io/project-id --dart-define=SENTRY_ENVIRONMENT=production
```

---

## 4. Useful Sentry Features

### User Context

```python
# Django - in middleware or view
from sentry_sdk import set_user

set_user({
    "id": str(request.user.id),
    "email": request.user.email,
    "username": request.user.username,
})
```

```dart
// Flutter - after login
Sentry.configureScope((scope) {
  scope.setUser(SentryUser(
    id: user.id,
    email: user.email,
    username: user.username,
  ));
});
```

### Tags for Filtering

```python
# Django
from sentry_sdk import set_tag
set_tag("room_id", room.id)
```

```dart
// Flutter
Sentry.configureScope((scope) {
  scope.setTag('room_id', roomId);
});
```

### Performance Transactions

```python
# Django - automatic for views, manual for custom operations
from sentry_sdk import start_transaction

with start_transaction(op="task", name="fetch_deezer_tracks"):
    # long-running task
    pass
```

---

## 5. Alert Configuration (Sentry Dashboard)

1. Go to **Alerts** in Sentry
2. Create rules for:
   - **First occurrence** of new issues
   - **High frequency** errors (> 10 in 1 hour)
   - **Specific errors** (e.g., 500 errors, auth failures)
3. Set up notifications:
   - Email for critical issues
   - Slack/Discord webhooks (optional)

---

## 6. Source Maps (Optional but Recommended)

### Flutter

```bash
# Upload debug symbols for better stack traces
sentry-cli upload-dif --org your-org --project songspot-mobile ./build/app/outputs/
```

### Django

Source maps not needed for Python (stack traces are already readable).

---

## Quick Checklist

- [ ] Create Sentry account and projects
- [ ] Add `sentry-sdk[django]` to backend requirements
- [ ] Add `sentry_flutter` to mobile pubspec.yaml
- [ ] Configure DSN in environment variables
- [ ] Test error capture in staging
- [ ] Set up alert rules
- [ ] Verify user context is captured
- [ ] Configure release tracking
