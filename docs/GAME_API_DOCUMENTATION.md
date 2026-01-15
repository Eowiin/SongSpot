# SongSpot - Game API Documentation

## Overview

This API provides endpoints for managing game rooms, song packs, and tracks for the SongSpot application.

**Base URL:** `http://localhost:8000/api/game/`

**Authentication:** All endpoints require JWT authentication. Include the access token in the Authorization header.

```
Authorization: Bearer {access_token}
```

---

## Room Management

### 1. Create a Room

**Endpoint:** `POST /api/game/rooms/create/`

**Description:** Creates a new game room with an auto-generated unique 6-character code. The creator automatically becomes the host and is added to the room. Users can only create one room (subsequent calls return existing room).

**Request Body:**
```json
{}
```

**Note:** No request body needed - room code is auto-generated

**Success Response - New Room (201 Created):**
```json
{
  "room": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "room_code": "A1B2C3",
    "host_user": {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "username": "johndoe",
      "email": "john@example.com"
    },
    "users": [
      {
        "user": {
          "id": "550e8400-e29b-41d4-a716-446655440001",
          "username": "johndoe",
          "email": "john@example.com"
        },
        "joined_at": "2026-01-13T10:30:00Z"
      }
    ],
    "user_count": 1,
    "created_at": "2026-01-13T10:30:00Z"
  },
  "message": "Room created successfully"
}
```

**Success Response - Existing Room (200 OK):**
```json
{
  "room": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "room_code": "A1B2C3",
    "host_user": {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "username": "johndoe",
      "email": "john@example.com"
    },
    "users": [...],
    "user_count": 1,
    "created_at": "2026-01-13T10:30:00Z"
  },
  "message": "You already have a room"
}
```

---

### 2. Join a Room

**Endpoint:** `POST /api/game/rooms/join/`

**Description:** Join an existing room using its room code.

**Request Body:**
```json
{
  "room_code": "ABCD1234"
}
```

**Success Response (200 OK):**
```json
{
  "room": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "room_code": "ABCD1234",
    "host_user": {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "username": "johndoe",
      "email": "john@example.com"
    },
    "users": [
      {
        "user": {
          "id": "550e8400-e29b-41d4-a716-446655440001",
          "username": "johndoe",
          "email": "john@example.com"
        },
        "joined_at": "2026-01-13T10:30:00Z"
      },
      {
        "user": {
          "id": "550e8400-e29b-41d4-a716-446655440002",
          "username": "janedoe",
          "email": "jane@example.com"
        },
        "joined_at": "2026-01-13T10:35:00Z"
      }
    ],
    "user_count": 2,
    "created_at": "2026-01-13T10:30:00Z"
  },
  "message": "Joined room successfully"
}
```

**Error Responses:**

Room not found (400 Bad Request):
```json
{
  "room_code": ["Room not found."]
}
```

Already in room (400 Bad Request):
```json
{
  "error": "You are already in this room"
}
```

---

### 3. Leave a Room

**Endpoint:** `POST /api/game/rooms/{room_id}/leave/`

**Description:** Leave a room. If the host leaves and other users remain, host is transferred to another user. If everyone leaves, the room is deleted.

**URL Parameters:**
- `room_id` (UUID): The ID of the room to leave

**Success Response (200 OK):**
```json
{
  "message": "Left room successfully"
}
```

**Room deleted (200 OK):**
```json
{
  "message": "You left the room. Room has been deleted as it was empty."
}
```

**Error Response (400 Bad Request):**
```json
{
  "error": "You are not in this room"
}
```

---

### 4. Get Room Details

**Endpoint:** `GET /api/game/rooms/{room_id}/`

**Description:** Get detailed information about a specific room.

**URL Parameters:**
- `room_id` (UUID): The ID of the room

**Success Response (200 OK):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "room_code": "ABCD1234",
  "host_user": {
    "id": "550e8400-e29b-41d4-a716-446655440001",
    "username": "johndoe",
    "email": "john@example.com"
  },
  "users": [
    {
      "user": {
        "id": "550e8400-e29b-41d4-a716-446655440001",
        "username": "johndoe",
        "email": "john@example.com"
      },
      "joined_at": "2026-01-13T10:30:00Z"
    }
  ],
  "user_count": 1,
  "created_at": "2026-01-13T10:30:00Z"
}
```

**Error Response (404 Not Found):**
```json
{
  "detail": "Not found."
}
```

---

### 5. Get My Rooms

**Endpoint:** `GET /api/game/rooms/my-rooms/`

**Description:** Get all rooms that the authenticated user is currently in.

**Success Response (200 OK):**
```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "room_code": "ABCD1234",
    "host_user": {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "username": "johndoe",
      "email": "john@example.com"
    },
    "users": [
      {
        "user": {
          "id": "550e8400-e29b-41d4-a716-446655440001",
          "username": "johndoe",
          "email": "john@example.com"
        },
        "joined_at": "2026-01-13T10:30:00Z"
      }
    ],
    "user_count": 1,
    "created_at": "2026-01-13T10:30:00Z"
  }
]
```

---

## Song Packs

### 1. List Song Packs

**Endpoint:** `GET /api/game/packs/`

**Description:** Get all available song packs for purchase. Track details are hidden until purchased.

**Success Response (200 OK):**
```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440100",
    "name": "80s Classics",
    "description": "The best hits from the 1980s",
    "icon_url": "https://example.com/icons/80s.png",
    "track_count": 50,
    "created_at": "2026-01-01T00:00:00Z"
  },
  {
    "id": "550e8400-e29b-41d4-a716-446655440101",
    "name": "Rock Legends",
    "description": "Iconic rock songs from all eras",
    "icon_url": "https://example.com/icons/rock.png",
    "track_count": 75,
    "created_at": "2026-01-01T00:00:00Z"
  }
]
```

---

### 6. Get Daily Song for Room

**Endpoint:** `GET /api/game/rooms/{room_id}/daily-song/`

**Description:** Get today's song for a specific room. If no song exists for today, automatically selects a random unused track. Only accessible to users who are members of the room.

**URL Parameters:**
- `room_id` (UUID): The ID of the room

**Success Response - Existing Song (200 OK):**
```json
{
  "track": {
    "id": "550e8400-e29b-41d4-a716-446655440200",
    "title": "Do I Wanna Know?",
    "artist": "Arctic Monkeys",
    "preview_url": "https://cdns-preview-e.dzcdn.net/stream/...",
    "created_at": "2026-01-13T14:00:00Z"
  },
  "date": "2026-01-13",
  "message": "Today's song"
}
```

**Success Response - New Song Selected (200 OK):**
```json
{
  "track": {
    "id": "550e8400-e29b-41d4-a716-446655440201",
    "title": "R U Mine?",
    "artist": "Arctic Monkeys",
    "preview_url": "https://cdns-preview-e.dzcdn.net/stream/...",
    "created_at": "2026-01-13T14:00:00Z"
  },
  "date": "2026-01-13",
  "message": "New song selected for today"
}
```

**Error Response (403 Forbidden):**
```json
{
  "error": "You must be in the room to see the daily song"
}
```

**Error Response (404 Not Found):**
```json
{
  "error": "No tracks available. Please populate tracks using: python manage.py fetch_deezer_tracks"
}
```

**Notes:**
- Automatically prevents track repetition within a room until all tracks are used
- Once all tracks have been used, allows reusing tracks
- Each room gets a different random track each day
- The song selection happens automatically on the first request of the day

---

## Heardle-Style Game (Progressive Reveals)

The game uses a Heardle/Songless mechanic where users progressively reveal longer snippets of the song and can guess at any point.

### Snippet Progression
1. **Snippet 1:** 0.1 seconds (6 points)
2. **Snippet 2:** 0.5 seconds (5 points)
3. **Snippet 3:** 2 seconds (4 points)
4. **Snippet 4:** 4 seconds (3 points)
5. **Snippet 5:** 8 seconds (2 points)
6. **Snippet 6:** 15 seconds (1 point)

Users can either **skip** to the next snippet or **guess** the song. Incorrect guesses automatically advance to the next snippet.

### 7. Start/Get Game Session

**Endpoint:** `GET /api/game/rooms/{room_id}/daily-game/`

**Description:** Get or create today's game session. Returns the daily song and user's current progress.

**URL Parameters:**
- `room_id` (UUID): The ID of the room

**Success Response (200 OK):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440300",
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440001",
    "username": "johndoe",
    "email": "john@example.com"
  },
  "daily_song": {
    "id": "550e8400-e29b-41d4-a716-446655440250",
    "track": {
      "id": "550e8400-e29b-41d4-a716-446655440200",
      "title": "Do I Wanna Know?",
      "artist": "Arctic Monkeys",
      "preview_url": "https://cdns-preview-e.dzcdn.net/stream/...",
      "created_at": "2026-01-13T14:00:00Z"
    },
    "date": "2026-01-13",
    "created_at": "2026-01-13T08:00:00Z"
  },
  "current_snippet": 1,
  "guesses_made": 0,
  "correct_guess": false,
  "points_earned": null,
  "completed_at": null,
  "created_at": "2026-01-13T10:30:00Z"
}
```

**Error Response (403 Forbidden):**
```json
{
  "error": "You must be in the room to play the game"
}
```

---

### 8. Skip to Next Snippet

**Endpoint:** `POST /api/game/rooms/{room_id}/daily-game/skip/`

**Description:** Skip to the next snippet without guessing. Increments the snippet level.

**URL Parameters:**
- `room_id` (UUID): The ID of the room

**Success Response (200 OK):**
```json
{
  "current_snippet": 2,
  "message": "Skipped to snippet 2"
}
```

**Error Responses:**

**Already completed (400 Bad Request):**
```json
{
  "error": "You already guessed correctly",
  "current_snippet": 3
}
```

**At maximum snippet (400 Bad Request):**
```json
{
  "error": "Already at maximum snippet level",
  "current_snippet": 6
}
```

---

### 9. Submit a Guess

**Endpoint:** `POST /api/game/rooms/{room_id}/daily-game/guess/`

**Description:** Submit a guess for the song. Both title and artist must match (case-insensitive).

**URL Parameters:**
- `room_id` (UUID): The ID of the room

**Request Body:**
```json
{
  "title": "Do I Wanna Know?",
  "artist": "Arctic Monkeys"
}
```

**Success Response - Correct Guess (200 OK):**
```json
{
  "is_correct": true,
  "points_earned": 6,
  "snippet_number": 1,
  "message": "Correct! You earned 6 points!",
  "correct_answer": {
    "title": "Do I Wanna Know?",
    "artist": "Arctic Monkeys"
  }
}
```

**Success Response - Incorrect Guess (200 OK):**
```json
{
  "is_correct": false,
  "current_snippet": 2,
  "message": "Incorrect. Try again with snippet 2"
}
```

**Success Response - All Snippets Used (200 OK):**
```json
{
  "is_correct": false,
  "points_earned": 0,
  "message": "No more snippets. Better luck next time!",
  "correct_answer": {
    "title": "Do I Wanna Know?",
    "artist": "Arctic Monkeys"
  }
}
```

**Error Response - Already Completed (400 Bad Request):**
```json
{
  "error": "You already guessed correctly",
  "correct_answer": {
    "title": "Do I Wanna Know?",
    "artist": "Arctic Monkeys"
  }
}
```

**Validation Errors (400 Bad Request):**
```json
{
  "title": ["Title cannot be empty."],
  "artist": ["Artist cannot be empty."]
}
```

---

### 10. Get Leaderboard

**Endpoint:** `GET /api/game/rooms/{room_id}/daily-game/leaderboard/`

**Description:** Get today's leaderboard for the room. Shows all users who guessed correctly, ordered by points (highest first) and completion time (earliest first).

**URL Parameters:**
- `room_id` (UUID): The ID of the room

**Success Response (200 OK):**
```json
{
  "date": "2026-01-13",
  "leaderboard": [
    {
      "user": {
        "id": "550e8400-e29b-41d4-a716-446655440001",
        "username": "johndoe",
        "email": "john@example.com"
      },
      "points_earned": 6,
      "snippet_number": 1,
      "completed_at": "2026-01-13T10:35:12Z"
    },
    {
      "user": {
        "id": "550e8400-e29b-41d4-a716-446655440002",
        "username": "janedoe",
        "email": "jane@example.com"
      },
      "points_earned": 4,
      "snippet_number": 3,
      "completed_at": "2026-01-13T11:20:45Z"
    }
  ]
}
```

**Notes:**
- Only shows users who guessed correctly
- Sorted by points (descending), then by completion time (ascending)
- Empty leaderboard if no one has guessed correctly yet

---

## Room Chat

### 11. Get Room Messages

**Endpoint:** `GET /api/game/rooms/{room_id}/messages/?limit=50&offset=0`

**Description:** Get messages from the room chat. Supports pagination.

**URL Parameters:**
- `room_id` (UUID): The ID of the room

**Query Parameters:**
- `limit` (int, optional): Number of messages to retrieve (default: 50, max: 100)
- `offset` (int, optional): Number of messages to skip (default: 0)

**Success Response (200 OK):**
```json
{
  "messages": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440400",
      "user": {
        "id": "550e8400-e29b-41d4-a716-446655440001",
        "username": "johndoe",
        "email": "john@example.com"
      },
      "message": "I think I know this one!",
      "created_at": "2026-01-13T10:45:00Z"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440401",
      "user": {
        "id": "550e8400-e29b-41d4-a716-446655440002",
        "username": "janedoe",
        "email": "jane@example.com"
      },
      "message": "Good luck everyone!",
      "created_at": "2026-01-13T10:30:00Z"
    }
  ],
  "limit": 50,
  "offset": 0
}
```

---

### 12. Post a Message

**Endpoint:** `POST /api/game/rooms/{room_id}/messages/`

**Description:** Post a message to the room chat.

**URL Parameters:**
- `room_id` (UUID): The ID of the room

**Request Body:**
```json
{
  "message": "This song is amazing!"
}
```

**Success Response (201 Created):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440402",
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440001",
    "username": "johndoe",
    "email": "john@example.com"
  },
  "message": "This song is amazing!",
  "created_at": "2026-01-13T10:50:00Z"
}
```

**Validation Errors (400 Bad Request):**
```json
{
  "message": ["Message cannot be empty."]
}
```

**Notes:**
- Maximum message length: 500 characters
- Messages are ordered by creation time (newest first)
- Consider implementing rate limiting on the frontend (e.g., 1 message per 2 seconds)

---

## Tracks

### 1. List All Tracks

**Endpoint:** `GET /api/game/tracks/`

**Description:** Get list of all available tracks (primarily for admin purposes).

**Success Response (200 OK):**
```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440200",
    "title": "Billie Jean",
    "artist": "Michael Jackson",
    "preview_url": "https://cdns-preview-a.dzcdn.net/stream/...",
    "created_at": "2026-01-01T00:00:00Z"
  },
  {
    "id": "550e8400-e29b-41d4-a716-446655440201",
    "title": "Bohemian Rhapsody",
    "artist": "Queen",
    "preview_url": "https://cdns-preview-a.dzcdn.net/stream/...",
    "created_at": "2026-01-01T00:00:00Z"
  }
]
```

---

## Game Flow

### How the Game Works

1. **Room Creation:**
   - User creates a room (unique code auto-generated)
   - User becomes the host and is automatically added to the room
   - User can only have one room at a time

2. **Friends Join:**
   - Friends use the room code to join the room
   - All users in the room can see each other

3. **Daily Song Selection:**
   - Each room gets one random song per day
   - Song is automatically selected on first game session request
   - Same song for all users in the room for 24 hours

4. **Heardle-Style Gameplay:**
   - Users have 24 hours to guess the song
   - Progressive audio reveals: 0.1s, 0.5s, 2s, 4s, 8s, 15s
   - **Game Flow:**
     1. Call `GET /daily-game/` to start - get snippet level 1 (0.1s)
     2. Listen to snippet on frontend (play first N seconds of preview_url)
     3. Either skip to next snippet OR submit a guess
     4. If guess is wrong, automatically advance to next snippet
     5. If guess is correct, earn points based on snippet number (6pts for snippet 1, down to 1pt for snippet 6)
   - Chat with room members while playing

5. **Scoring:**
   - Snippet 1 (0.1s): 6 points
   - Snippet 2 (0.5s): 5 points
   - Snippet 3 (2s): 4 points
   - Snippet 4 (4s): 3 points
   - Snippet 5 (8s): 2 points
   - Snippet 6 (15s): 1 point
   - After 6 snippets, answer is revealed with 0 points

6. **Leaderboard:**
   - View daily rankings for each room
   - Sorted by points (highest first), then completion time (earliest first)
   - Only shows users who guessed correctly

7. **Room Chat:**
   - Simple message board for discussing the song
   - 500 character limit per message
   - Pagination support for message history

### Frontend Audio Handling

**Important:** The backend provides the full `preview_url` from Deezer (typically 30 seconds). The frontend must:
- Play only the first N seconds based on `current_snippet`:
  - Snippet 1: Play 0.1 seconds
  - Snippet 2: Play 0.5 seconds
  - Snippet 3: Play 2 seconds
  - Snippet 4: Play 4 seconds
  - Snippet 5: Play 8 seconds
  - Snippet 6: Play 15 seconds
- Stop playback automatically after the snippet duration
- Prevent users from manually seeking forward in the audio

---

## Error Codes

| Status Code | Description |
|-------------|-------------|
| 200 | Success |
| 201 | Resource created successfully |
| 400 | Bad request (validation errors) |
| 401 | Unauthorized (invalid or expired token) |
| 404 | Not found |
| 500 | Internal server error |

---

## Testing with cURL

### Create a Room
```bash
curl -X POST http://localhost:8000/api/game/rooms/create/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'
```

### Join a Room
```bash
curl -X POST http://localhost:8000/api/game/rooms/join/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"room_code": "TEST1234"}'
```

### Get My Rooms
```bash
curl -X GET http://localhost:8000/api/game/rooms/my-rooms/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

### Get Daily Song for Room
```bash
curl -X GET http://localhost:8000/api/game/rooms/ROOM_ID/daily-song/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

### Start Game Session
```bash
curl -X GET http://localhost:8000/api/game/rooms/ROOM_ID/daily-game/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

### Skip to Next Snippet
```bash
curl -X POST http://localhost:8000/api/game/rooms/ROOM_ID/daily-game/skip/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

### Submit a Guess
```bash
curl -X POST http://localhost:8000/api/game/rooms/ROOM_ID/daily-game/guess/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title": "Do I Wanna Know?", "artist": "Arctic Monkeys"}'
```

### Get Leaderboard
```bash
curl -X GET http://localhost:8000/api/game/rooms/ROOM_ID/daily-game/leaderboard/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

### Get Room Messages
```bash
curl -X GET "http://localhost:8000/api/game/rooms/ROOM_ID/messages/?limit=50&offset=0" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

### Post a Message
```bash
curl -X POST http://localhost:8000/api/game/rooms/ROOM_ID/messages/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message": "This song is amazing!"}'
```

### List Song Packs
```bash
curl -X GET http://localhost:8000/api/game/packs/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

---

## Next Features to Implement

- [ ] Pack purchase endpoint
- [ ] Pack-based daily song selection
- [ ] Real-time gameplay with WebSockets (optional)
- [ ] User statistics and history
