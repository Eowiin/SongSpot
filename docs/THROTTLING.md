# Throttling Guide

This project uses Django REST Framework (DRF) throttling to protect APIs from abuse.
Throttling is applied globally (all endpoints) and selectively for some actions
(auth, guesses, and chat).

## Current Configuration

Defined in `songspot_backend/songspot/settings.py`:

```
REST_FRAMEWORK = {
  'DEFAULT_THROTTLE_CLASSES': [
    'rest_framework.throttling.AnonRateThrottle',
    'rest_framework.throttling.UserRateThrottle',
  ],
  'DEFAULT_THROTTLE_RATES': {
    'anon': '20/minute',
    'user': '300/minute',
    'auth': '5/minute',
    'guess': '10/minute',
    'message': '30/minute',
  },
}
```

Custom throttle classes live in `songspot_backend/songspot/throttling.py`:
- `AuthRateThrottle` (`scope = 'auth'`)
- `GuessRateThrottle` (`scope = 'guess'`)
- `MessageRateThrottle` (`scope = 'message'`)
- `BurstRateThrottle` (`scope = 'burst'`, `rate = '3/second'`)

## Where Throttling Is Applied

- Global: all endpoints are limited by `AnonRateThrottle` and `UserRateThrottle`.
- Auth endpoints: typically use `AuthRateThrottle` in their view classes.
- Game guesses: use `GuessRateThrottle` on guess endpoints.
- Chat: use `MessageRateThrottle` on message endpoints.

## How to Customize

1) Update rates in `DEFAULT_THROTTLE_RATES` (settings):
   - Increase `user` if normal app usage hits 429s.
   - Keep `auth` and `guess` tighter for safety.

2) Apply specific throttles in views:
```
from songspot.throttling import GuessRateThrottle

class SubmitGuessView(APIView):
    throttle_classes = [GuessRateThrottle]
```

3) Disable throttling in local dev (optional):
```
if DEBUG:
    REST_FRAMEWORK['DEFAULT_THROTTLE_CLASSES'] = []
```

## Troubleshooting

- If the app fails to load data intermittently, check for HTTP 429 responses.
- Search for `429` in backend logs or mobile logs to confirm throttling.
- Reduce API call frequency on the client (e.g., debounce search).
