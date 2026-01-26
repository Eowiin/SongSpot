import 'package:flutter/foundation.dart';
import '../models/pack.dart';
import '../services/api_service.dart';

class PackProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<SongPack> _packs = [];
  List<SongPack> _ownedPacks = [];
  SongPack? _currentPack;
  bool _isLoading = false;
  String? _errorMessage;

  List<SongPack> get packs => _packs;
  List<SongPack> get ownedPacks => _ownedPacks;
  SongPack? get currentPack => _currentPack;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadPacks(String roomId) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response = await _apiService.getPacks(roomId: roomId);
      _packs = response
          .map((item) => SongPack.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadPackDetail({
    required String roomId,
    required String packId,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response = await _apiService.getPackDetail(roomId: roomId, packId: packId);
      _currentPack = SongPack.fromJson(response);
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMyPacks(String roomId) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response = await _apiService.getMyPacks(roomId: roomId);
      _ownedPacks = response
          .map((item) => SongPack.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> purchasePack({
    required String roomId,
    required String packId,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response = await _apiService.purchasePack(roomId: roomId, packId: packId);
      final packJson = response['pack'] as Map<String, dynamic>;
      final updatedPack = SongPack.fromJson(packJson);

      _packs = _packs.map((pack) {
        return pack.id == updatedPack.id ? updatedPack : pack;
      }).toList();
      final ownedIndex = _ownedPacks.indexWhere((pack) => pack.id == updatedPack.id);
      if (updatedPack.isOwned) {
        if (ownedIndex == -1) {
          _ownedPacks = [..._ownedPacks, updatedPack];
        } else {
          _ownedPacks = _ownedPacks
              .asMap()
              .entries
              .map((entry) => entry.key == ownedIndex ? updatedPack : entry.value)
              .toList();
        }
      } else if (ownedIndex != -1) {
        _ownedPacks = _ownedPacks.where((pack) => pack.id != updatedPack.id).toList();
      }
      _currentPack = updatedPack;
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
