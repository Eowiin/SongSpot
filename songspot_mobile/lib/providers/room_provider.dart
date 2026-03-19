import 'package:flutter/foundation.dart';
import '../models/room.dart';
import '../services/api_service.dart';

class RoomProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<Room> _myRooms = [];
  Room? _currentRoom;
  bool _isLoading = false;
  String? _errorMessage;

  List<Room> get myRooms => List.unmodifiable(_myRooms);
  Room? get currentRoom => _currentRoom;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void _syncRoom(Room room) {
    _currentRoom = room;
    final index = _myRooms.indexWhere((r) => r.id == room.id);
    if (index != -1) {
      _myRooms[index] = room;
    }
  }

  /// Create a new room
  Future<Room?> createRoom() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response = await _apiService.createRoom();
      final room = Room.fromJson(response['room'] as Map<String, dynamic>);

      _syncRoom(room);
      await loadMyRooms();

      _isLoading = false;
      notifyListeners();
      return room;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Join a room by code
  Future<Room?> joinRoom(String roomCode) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response = await _apiService.joinRoom(roomCode);
      final room = Room.fromJson(response['room'] as Map<String, dynamic>);

      _syncRoom(room);
      await loadMyRooms();

      _isLoading = false;
      notifyListeners();
      return room;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Load all rooms the user is in
  Future<void> loadMyRooms() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response = await _apiService.getMyRooms();
      _myRooms = response
          .map((room) => Room.fromJson(room as Map<String, dynamic>))
          .toList();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get room details
  Future<void> loadRoomDetails(String roomId) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response = await _apiService.getRoomDetails(roomId);
      _syncRoom(Room.fromJson(response));

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Leave a room
  Future<bool> leaveRoom(String roomId) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await _apiService.leaveRoom(roomId);

      if (_currentRoom?.id == roomId) {
        _currentRoom = null;
      }
      await loadMyRooms();

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Leave a room without toggling global loading state.
  /// Useful for swipe-to-delete flows with optimistic UI.
  Future<bool> leaveRoomSilently(String roomId) async {
    try {
      _errorMessage = null;
      await _apiService.leaveRoom(roomId);

      _myRooms = _myRooms.where((room) => room.id != roomId).toList();
      if (_currentRoom?.id == roomId) {
        _currentRoom = null;
      }
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Rename a room (host only)
  Future<Room?> renameRoom(String roomId, String? name) async {
    try {
      _errorMessage = null;

      final response = await _apiService.renameRoom(roomId, name);
      final room = Room.fromJson(response['room'] as Map<String, dynamic>);

      _syncRoom(room);

      notifyListeners();
      return room;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Set current room
  void setCurrentRoom(Room room) {
    _syncRoom(room);
    notifyListeners();
  }

  void updateRoomDailyModes(String roomId, List<RoomDailyMode> dailyModes) {
    final current = _currentRoom;
    if (current != null && current.id == roomId) {
      _currentRoom = current.copyWith(dailyModes: dailyModes);
    }
    final index = _myRooms.indexWhere((room) => room.id == roomId);
    if (index != -1) {
      _myRooms[index] = _myRooms[index].copyWith(dailyModes: dailyModes);
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>?> contributeToDailyMode({
    required String roomId,
    required String mode,
    required int amount,
  }) async {
    try {
      _errorMessage = null;
      final response = await _apiService.contributeToDailyMode(
        roomId: roomId,
        mode: mode,
        amount: amount,
      );
      final roomJson = response['room'] as Map<String, dynamic>?;
      if (roomJson != null) {
        _syncRoom(Room.fromJson(roomJson));
      }
      notifyListeners();
      return response;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  void clearCurrentRoom() {
    _currentRoom = null;
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
