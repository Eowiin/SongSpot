import json
import logging
import os
import threading
from typing import Iterable

from django.conf import settings
from django.utils import timezone

from authentication.models import UserDevicePushToken

try:
    import firebase_admin
    from firebase_admin import credentials, messaging
except Exception:  # pragma: no cover - optional dependency at runtime
    firebase_admin = None
    credentials = None
    messaging = None


logger = logging.getLogger(__name__)
_firebase_init_lock = threading.Lock()
_firebase_initialized = False


def _fcm_configured() -> bool:
    return bool(
        getattr(settings, 'FCM_SERVICE_ACCOUNT_PATH', None)
        or getattr(settings, 'FCM_SERVICE_ACCOUNT_JSON', None)
    )


def _initialize_firebase() -> bool:
    global _firebase_initialized

    if _firebase_initialized:
        return True

    if not _fcm_configured():
        return False

    if firebase_admin is None or credentials is None:
        logger.warning('firebase-admin is not installed; push notifications are disabled.')
        return False

    with _firebase_init_lock:
        if _firebase_initialized:
            return True

        try:
            firebase_admin.get_app()
            _firebase_initialized = True
            return True
        except ValueError:
            pass

        cred_obj = None
        service_account_json = getattr(settings, 'FCM_SERVICE_ACCOUNT_JSON', None)
        service_account_path = getattr(settings, 'FCM_SERVICE_ACCOUNT_PATH', None)

        if service_account_json:
            try:
                cred_obj = credentials.Certificate(json.loads(service_account_json))
            except json.JSONDecodeError:
                logger.exception('Invalid FCM_SERVICE_ACCOUNT_JSON.')
                return False
        elif service_account_path:
            if not os.path.exists(service_account_path):
                logger.warning('FCM service account path does not exist: %s', service_account_path)
                return False
            cred_obj = credentials.Certificate(service_account_path)
        else:
            return False

        firebase_admin.initialize_app(cred_obj)
        _firebase_initialized = True
        return True


def _chunks(items: list[str], size: int) -> Iterable[list[str]]:
    for i in range(0, len(items), size):
        yield items[i:i + size]


def _mark_tokens_inactive(tokens: list[str]) -> None:
    if not tokens:
        return
    UserDevicePushToken.objects.filter(token__in=tokens, is_active=True).update(is_active=False)


def send_push_to_users(
    user_ids: list[str],
    *,
    title: str,
    body: str,
    data: dict | None = None,
    notification_type: str = 'general',
) -> dict:
    if not user_ids or not _initialize_firebase():
        return {'success_count': 0, 'failure_count': 0, 'skipped': True}

    devices = UserDevicePushToken.objects.filter(
        user_id__in=user_ids,
        is_active=True,
    )
    if notification_type == 'daily_song':
        devices = devices.filter(daily_song_enabled=True)
    elif notification_type == 'message':
        devices = devices.filter(messages_enabled=True)

    tokens = list(devices.values_list('token', flat=True).distinct())
    if not tokens:
        return {'success_count': 0, 'failure_count': 0, 'skipped': True}

    payload = {}
    for key, value in (data or {}).items():
        if value is None:
            continue
        payload[str(key)] = str(value)

    success_count = 0
    failure_count = 0
    invalid_tokens: list[str] = []

    for token_batch in _chunks(tokens, 500):
        message = messaging.MulticastMessage(
            tokens=token_batch,
            notification=messaging.Notification(title=title, body=body),
            data=payload,
            android=messaging.AndroidConfig(priority='high'),
            apns=messaging.APNSConfig(
                headers={'apns-priority': '10'},
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound='default', content_available=True),
                ),
            ),
        )

        try:
            if hasattr(messaging, 'send_each_for_multicast'):
                response = messaging.send_each_for_multicast(message)
            else:  # Older SDK fallback
                response = messaging.send_multicast(message)
        except Exception:
            logger.exception('FCM multicast send failed.')
            failure_count += len(token_batch)
            continue

        success_count += response.success_count
        failure_count += response.failure_count

        for index, send_response in enumerate(response.responses):
            if send_response.success:
                continue
            error_text = str(send_response.exception).lower()
            if any(
                marker in error_text
                for marker in (
                    'registration-token-not-registered',
                    'registration token is not a valid',
                    'requested entity was not found',
                    'unregistered',
                )
            ):
                invalid_tokens.append(token_batch[index])

    _mark_tokens_inactive(invalid_tokens)
    UserDevicePushToken.objects.filter(token__in=tokens, is_active=True).update(last_seen_at=timezone.now())

    return {
        'success_count': success_count,
        'failure_count': failure_count,
        'invalid_token_count': len(invalid_tokens),
    }
