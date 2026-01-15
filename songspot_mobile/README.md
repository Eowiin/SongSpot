# SongSpot - Flutter Mobile App

A Flutter mobile application for the SongSpot music guessing game.

## Features

- **User Authentication**: Register and login with JWT token management
- **Room Management**: Create and join game rooms using room codes
- **Heardle-Style Gameplay**: Progressive audio reveals (6 snippets: 0.1s, 0.5s, 2s, 4s, 8s, 15s)
- **Daily Challenges**: One song per day per room
- **Leaderboard**: Compete with friends and see daily rankings
- **Room Chat**: Chat with other players in your room
- **Modern UI**: Beautiful dark theme with gradients and smooth animations

## Tech Stack

- **Flutter**: 3.35.5
- **State Management**: Provider
- **Networking**: HTTP & Dio
- **Storage**: flutter_secure_storage (JWT tokens)
- **Audio**: just_audio
- **UI**: google_fonts, shimmer, lottie

## Prerequisites

- Flutter SDK 3.35.5 or higher
- Dart 3.9.2 or higher
- iOS Simulator or Android Emulator
- Django backend server running (see backend README)

## Getting Started

### 1. Install Dependencies

```bash
flutter pub get
```

### 2. Configure Backend URL

Create a `.env` file (or copy `.env.example`) and set `API_BASE_URL`:

```bash
cp .env.example .env
```

```env
API_BASE_URL=http://YOUR_IP_ADDRESS:8000/api
```

**Important:**
- For iOS Simulator: Use `http://localhost:8000/api`
- For Android Emulator: Use `http://10.0.2.2:8000/api`
- For Physical Device: Use your computer's local IP (e.g., `http://192.168.1.100:8000/api`)

### 3. Run the App

```bash
# Run on iOS
flutter run

# Run on Android
flutter run

# Or select a device
flutter devices
flutter run -d <device-id>
```

## Project Structure

```
lib/
├── config/
│   ├── api_config.dart          # API endpoints configuration
│   └── app_theme.dart            # App theme (colors, gradients, styles)
├── models/
│   ├── user.dart                 # User model
│   ├── track.dart                # Track model
│   ├── room.dart                 # Room model
│   ├── game_session.dart         # Game session model
│   └── message.dart              # Chat message model
├── services/
│   ├── api_service.dart          # HTTP API client
│   ├── storage_service.dart      # Secure storage for tokens
│   └── audio_service.dart        # Audio playback service
├── providers/
│   ├── auth_provider.dart        # Authentication state management
│   ├── room_provider.dart        # Room state management
│   └── game_provider.dart        # Game state management
├── screens/
│   ├── auth/
│   │   ├── login_screen.dart     # Login screen
│   │   └── register_screen.dart  # Registration screen
│   ├── home/
│   │   └── home_screen.dart      # Home screen (room list)
│   ├── room/
│   │   └── room_detail_screen.dart  # Room details
│   └── game/
│       ├── game_screen.dart         # Main gameplay screen
│       ├── leaderboard_screen.dart  # Leaderboard
│       └── chat_screen.dart         # Room chat
├── widgets/
│   ├── gradient_button.dart      # Reusable gradient button
│   └── custom_text_field.dart    # Reusable text field
└── main.dart                      # App entry point
```

## How to Play

1. **Register/Login**: Create an account or login with existing credentials
2. **Create or Join Room**:
   - Create a new room (you become the host)
   - Or join a room using a 6-character room code
3. **Play Daily Challenge**:
   - Tap "Play Today's Song" in your room
   - Listen to progressively longer audio snippets
   - Try to guess the song title and artist
   - Each correct guess earns points (6 points for snippet 1, down to 1 point for snippet 6)
4. **View Leaderboard**: See how you rank against your friends
5. **Chat**: Discuss the song with other room members

## API Endpoints

The app connects to the following backend endpoints:

### Authentication
- `POST /api/auth/register/` - User registration
- `POST /api/auth/login/` - User login
- `POST /api/auth/logout/` - Logout
- `POST /api/auth/token/refresh/` - Refresh access token
- `GET /api/auth/profile/` - Get user profile

### Rooms
- `POST /api/game/rooms/create/` - Create room
- `POST /api/game/rooms/join/` - Join room
- `GET /api/game/rooms/my-rooms/` - Get user's rooms
- `GET /api/game/rooms/<id>/` - Get room details
- `POST /api/game/rooms/<id>/leave/` - Leave room

### Game
- `GET /api/game/rooms/<id>/daily-game/` - Start game session
- `POST /api/game/rooms/<id>/daily-game/skip/` - Skip snippet
- `POST /api/game/rooms/<id>/daily-game/guess/` - Submit guess
- `GET /api/game/rooms/<id>/daily-game/leaderboard/` - Get leaderboard

### Chat
- `GET /api/game/rooms/<id>/messages/` - Get messages
- `POST /api/game/rooms/<id>/messages/` - Send message

## Common Issues

### iOS Audio Permission
Add to `ios/Runner/Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs access to play audio</string>
```

### Android Network Permission
Already configured in `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

### Connection Refused
- Make sure the Django backend is running
- Check the API base URL in `api_config.dart`
- For Android Emulator, use `10.0.2.2` instead of `localhost`
- For physical devices, use your computer's local IP address

### SSL/HTTPS Issues
For development, the app uses HTTP. For production:
1. Configure your backend with SSL
2. Update `baseUrl` to use `https://`
3. For Android, configure network security

## Building for Release

### iOS
```bash
flutter build ios --release
```

### Android
```bash
flutter build apk --release
# Or for app bundle
flutter build appbundle --release
```

## License

MIT License
