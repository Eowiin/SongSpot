# SongSpot - Authentication API Documentation

## Overview

This API provides JWT-based authentication for the SongSpot mobile application. All endpoints return JSON responses.

**Base URL:** `http://localhost:8000/api/auth/`

## Security Features

- **JWT Access Token:** Valid for 1 hour
- **JWT Refresh Token:** Valid for 90 days
- **Token Rotation:** Refresh tokens are automatically rotated on each refresh for enhanced security
- **Token Blacklisting:** Old refresh tokens are blacklisted when rotated or during logout

## Authentication Endpoints

### 1. Register a New User

**Endpoint:** `POST /api/auth/register/`

**Headers:**
```
Content-Type: application/json
```

**Request Body:**
```json
{
  "email": "user@example.com",
  "username": "johndoe",
  "password": "SecurePassword123!",
  "password_confirm": "SecurePassword123!"
}
```

**Success Response (201 Created):**
```json
{
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "username": "johndoe"
  },
  "tokens": {
    "access": "eyJ0eXAiOiJKV1QiLCJhbGc...",
    "refresh": "eyJ0eXAiOiJKV1QiLCJhbGc..."
  },
  "message": "User registered successfully"
}
```

**Error Response (400 Bad Request):**
```json
{
  "email": ["This field is required."],
  "password": ["Password fields didn't match."]
}
```

---

### 2. Login

**Endpoint:** `POST /api/auth/login/`

**Headers:**
```
Content-Type: application/json
```

**Request Body:**
```json
{
  "email": "user@example.com",
  "password": "SecurePassword123!"
}
```

**Success Response (200 OK):**
```json
{
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "username": "johndoe"
  },
  "tokens": {
    "access": "eyJ0eXAiOiJKV1QiLCJhbGc...",
    "refresh": "eyJ0eXAiOiJKV1QiLCJhbGc..."
  },
  "message": "Login successful"
}
```

**Error Response (401 Unauthorized):**
```json
{
  "error": "Invalid credentials"
}
```

---

### 3. Refresh Access Token

**Endpoint:** `POST /api/auth/token/refresh/`

**Headers:**
```
Content-Type: application/json
```

**Request Body:**
```json
{
  "refresh": "eyJ0eXAiOiJKV1QiLCJhbGc..."
}
```

**Success Response (200 OK):**
```json
{
  "access": "eyJ0eXAiOiJKV1QiLCJhbGc...",
  "refresh": "eyJ0eXAiOiJKV1QiLCJhbGc..."
}
```

**Note:** Both tokens are returned. The old refresh token is blacklisted, and a new one is issued for security.

**Error Response (401 Unauthorized):**
```json
{
  "error": "Invalid or expired refresh token"
}
```

---

### 4. Get User Profile

**Endpoint:** `GET /api/auth/profile/`

**Headers:**
```
Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGc...
```

**Success Response (200 OK):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "user@example.com",
  "username": "johndoe"
}
```

**Error Response (401 Unauthorized):**
```json
{
  "detail": "Authentication credentials were not provided."
}
```

---

### 5. Logout

**Endpoint:** `POST /api/auth/logout/`

**Headers:**
```
Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGc...
Content-Type: application/json
```

**Request Body:**
```json
{
  "refresh": "eyJ0eXAiOiJKV1QiLCJhbGc..."
}
```

**Success Response (200 OK):**
```json
{
  "message": "Logout successful. Tokens have been invalidated."
}
```

**Error Response (400 Bad Request):**
```json
{
  "error": "Invalid token"
}
```

---

## Mobile App Implementation Guide

### 1. Initial Setup

When a user registers or logs in, you'll receive two tokens:
- **Access Token** (short-lived, 1 hour)
- **Refresh Token** (long-lived, 90 days)

Store both tokens securely in your mobile app's secure storage:
- iOS: Keychain
- Android: EncryptedSharedPreferences or Keystore

### 2. Making Authenticated Requests

For all authenticated API calls, include the access token in the Authorization header:

```
Authorization: Bearer {access_token}
```

### 3. Handling Token Expiration

When an API call returns a 401 Unauthorized error:

1. Check if you have a valid refresh token
2. Call the refresh endpoint with your refresh token
3. Store the new access and refresh tokens
4. Retry the original API call with the new access token

### 4. Example Flow (Pseudocode)

```javascript
async function makeAuthenticatedRequest(url, options) {
  // Add access token to request
  options.headers = {
    ...options.headers,
    'Authorization': `Bearer ${getAccessToken()}`
  };

  let response = await fetch(url, options);

  // If token expired, refresh and retry
  if (response.status === 401) {
    const refreshed = await refreshAccessToken();

    if (refreshed) {
      // Retry with new token
      options.headers['Authorization'] = `Bearer ${getAccessToken()}`;
      response = await fetch(url, options);
    } else {
      // Refresh failed, redirect to login
      redirectToLogin();
    }
  }

  return response;
}

async function refreshAccessToken() {
  const response = await fetch('/api/auth/token/refresh/', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ refresh: getRefreshToken() })
  });

  if (response.ok) {
    const data = await response.json();
    saveAccessToken(data.access);
    saveRefreshToken(data.refresh);
    return true;
  }

  return false;
}
```

### 5. Logout Implementation

When user logs out:
1. Call the logout endpoint with the refresh token
2. Clear both tokens from secure storage
3. Clear any cached user data
4. Redirect to login screen

### 6. Security Best Practices

- **Never** log tokens to console or analytics
- **Never** store tokens in plain text
- Clear tokens when the app detects it's been tampered with
- Implement certificate pinning for production
- Use HTTPS only in production

---

## Error Codes

| Status Code | Description |
|-------------|-------------|
| 200 | Success |
| 201 | Resource created successfully |
| 400 | Bad request (validation errors) |
| 401 | Unauthorized (invalid or expired token) |
| 500 | Internal server error |

---

## Development Setup

1. Install dependencies: `pip install -r requirements.txt`
2. Copy `.env.example` to `.env` and set values
3. Run migrations: `python manage.py migrate`
4. Start server: `python manage.py runserver`

---

## Questions or Issues?

Contact the backend team for support.
