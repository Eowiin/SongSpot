from rest_framework.response import Response


class ErrorCode:
    INVALID_CREDENTIALS = 'INVALID_CREDENTIALS'
    INVALID_PASSWORD = 'INVALID_PASSWORD'
    INVALID_CURRENT_PASSWORD = 'INVALID_CURRENT_PASSWORD'
    INVALID_TOKEN = 'INVALID_TOKEN'
    INVALID_OR_EXPIRED_REFRESH_TOKEN = 'INVALID_OR_EXPIRED_REFRESH_TOKEN'
    REFRESH_TOKEN_REQUIRED = 'REFRESH_TOKEN_REQUIRED'
    PASSWORD_RESET_UNAVAILABLE = 'PASSWORD_RESET_UNAVAILABLE'
    MISSING_REQUIRED_FIELDS = 'MISSING_REQUIRED_FIELDS'


def error_response(
    *,
    code: str,
    message: str,
    status_code: int,
    params: dict | None = None,
    reason: str | None = None,
    **extra,
):
    payload = {
        'error': message,
        'message': message,
        'error_code': code,
        'params': params or {},
    }
    if reason:
        payload['reason'] = reason
    payload.update(extra)
    return Response(payload, status=status_code)
