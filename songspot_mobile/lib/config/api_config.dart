import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  // Base URL for the API
  static String get baseUrl =>
      dotenv.env['API_BASE_URL']?.trim().isNotEmpty == true
          ? dotenv.env['API_BASE_URL']!.trim()
          : 'http://localhost:8000/api';

  // Auth endpoints
  static const String authRegister = '/auth/register/';
  static const String authLogin = '/auth/login/';
  static const String authLogout = '/auth/logout/';
  static const String authRefresh = '/auth/token/refresh/';
  static const String authProfile = '/auth/profile/';

  // Game endpoints
  static const String roomsCreate = '/game/rooms/create/';
  static const String roomsJoin = '/game/rooms/join/';
  static String roomsDetail(String roomId) => '/game/rooms/$roomId/';
  static String roomsLeave(String roomId) => '/game/rooms/$roomId/leave/';
  static String roomsRename(String roomId) => '/game/rooms/$roomId/rename/';
  static const String roomsMyRooms = '/game/rooms/my-rooms/';
  static String roomsDailySong(String roomId) => '/game/rooms/$roomId/daily-song/';

  // Game play endpoints
  static String dailyGame(String roomId) => '/game/rooms/$roomId/daily-game/';
  static String dailyGameSkip(String roomId) => '/game/rooms/$roomId/daily-game/skip/';
  static String dailyGameGuess(String roomId) => '/game/rooms/$roomId/daily-game/guess/';
  static String dailyGameLeaderboard(String roomId) => '/game/rooms/$roomId/daily-game/leaderboard/';

  // Chat endpoints
  static String roomMessages(String roomId) => '/game/rooms/$roomId/messages/';

  // Packs and tracks
  static const String packs = '/game/packs/';
  static const String tracks = '/game/tracks/';
  static const String searchTracks = '/game/tracks/search/';

  // Request timeout
  static const Duration timeout = Duration(seconds: 30);
}
