# Testing Authentication Endpoints

## Quick Test Guide

### Prerequisites
```bash
# Start the development server
cd blindtest_friends
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

### Test 3: Get User Profile (Protected Endpoint)

```bash
# Replace YOUR_ACCESS_TOKEN with the token from register/login
curl -X GET http://localhost:8000/api/auth/profile/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

Expected: 200 OK with user profile data

### Test 4: Refresh Token

```bash
# Replace YOUR_REFRESH_TOKEN with the refresh token from register/login
curl -X POST http://localhost:8000/api/auth/token/refresh/ \
  -H "Content-Type: application/json" \
  -d '{
    "refresh": "YOUR_REFRESH_TOKEN"
  }'
```

Expected: 200 OK with new access and refresh tokens

### Test 5: Logout

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

### Test 6: Try Using Blacklisted Token (Should Fail)

Try using the refresh token from Test 5 again:

```bash
curl -X POST http://localhost:8000/api/auth/token/refresh/ \
  -H "Content-Type: application/json" \
  -d '{
    "refresh": "YOUR_BLACKLISTED_REFRESH_TOKEN"
  }'
```

Expected: 401 Unauthorized - token has been blacklisted
