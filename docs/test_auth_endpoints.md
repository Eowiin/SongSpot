# Testing Authentication Endpoints

## Quick Test Guide

### Prerequisites
```bash
# Start the development server
cd songspot_backend
source ../.venv/bin/activate
python manage.py runserver
```

### Test 1: Register a New User

```bash
curl -X POST http://localhost:8000/api/auth/register/ \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "username": "testuser",
    "password": "TestPass123!",
    "password_confirm": "TestPass123!"
  }'
```

Expected: 201 Created with user data and tokens

### Test 2: Login

```bash
curl -X POST http://localhost:8000/api/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "TestPass123!"
  }'
```

Expected: 200 OK with user data and tokens

Save the access token for the next tests!

### Test 3: Request Password Reset Email

```bash
curl -X POST http://localhost:8000/api/auth/password-reset/request/ \
  -H "Content-Type: application/json" \
  -d '{
    "email": "TEST@EXAMPLE.COM",
    "locale": "en"
  }'
```

Expected: 200 OK with a generic success message. The email is normalized to lowercase server-side.

### Test 4: Get User Profile (Protected Endpoint)

```bash
# Replace YOUR_ACCESS_TOKEN with the token from register/login
curl -X GET http://localhost:8000/api/auth/profile/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

Expected: 200 OK with user profile data

### Test 5: Refresh Token

```bash
# Replace YOUR_REFRESH_TOKEN with the refresh token from register/login
curl -X POST http://localhost:8000/api/auth/token/refresh/ \
  -H "Content-Type: application/json" \
  -d '{
    "refresh": "YOUR_REFRESH_TOKEN"
  }'
```

Expected: 200 OK with new access and refresh tokens

### Test 6: Logout

```bash
# Replace YOUR_ACCESS_TOKEN and YOUR_REFRESH_TOKEN
curl -X POST http://localhost:8000/api/auth/logout/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "refresh": "YOUR_REFRESH_TOKEN"
  }'
```

Expected: 200 OK with logout confirmation message

### Test 7: Try Using Blacklisted Token (Should Fail)

Try using the refresh token from Test 5 again:

```bash
curl -X POST http://localhost:8000/api/auth/token/refresh/ \
  -H "Content-Type: application/json" \
  -d '{
    "refresh": "YOUR_BLACKLISTED_REFRESH_TOKEN"
  }'
```

Expected: 401 Unauthorized - token has been blacklisted

### Password Reset Security Notes

- The password reset endpoint is throttled more strictly than login/register.
- Current protection is `3/hour` per IP.
- A second request for the same normalized email is silently suppressed during the cooldown window.
- Reset links are temporary; the timeout is controlled by `PASSWORD_RESET_TIMEOUT`.
