import 'package:flutter/foundation.dart';
import '../models/pack_bundle.dart';
import '../services/api_service.dart';

class PackBundleProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  PackBundleSession? _session;
  List<Stem> _stems = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _guessResult;

  PackBundleSession? get session => _session;
  List<Stem> get stems => _stems;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get guessResult => _guessResult;

  Future<void> loadSession({required String roomId, required String packId}) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      _guessResult = null;
      notifyListeners();

      final response = await _apiService.getPackBundle(roomId: roomId, packId: packId);
      _session = PackBundleSession.fromJson(response['session'] as Map<String, dynamic>);
      _stems = (response['stems'] as List)
          .map((item) => Stem.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> skipStage({required String roomId, required String packId}) async {
    if (_session == null) return;
    try {
      _isLoading = true;
      _errorMessage = null;
      _guessResult = null;
      notifyListeners();

      final response = await _apiService.skipPackBundle(roomId: roomId, packId: packId);
      _session = PackBundleSession.fromJson(response['session'] as Map<String, dynamic>);
      _stems = (response['stems'] as List)
          .map((item) => Stem.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> submitGuess({
    required String roomId,
    required String packId,
    required String trackId,
  }) async {
    if (_session == null) return false;
    try {
      _isLoading = true;
      _errorMessage = null;
      _guessResult = null;
      notifyListeners();

      final response = await _apiService.guessPackBundle(
        roomId: roomId,
        packId: packId,
        trackId: trackId,
      );

      _session = PackBundleSession.fromJson(response['session'] as Map<String, dynamic>);
      _stems = (response['stems'] as List)
          .map((item) => Stem.fromJson(item as Map<String, dynamic>))
          .toList();
      final isCorrect = response['is_correct'] as bool? ?? false;
      final points = response['points_awarded'] as int? ?? 0;
      _guessResult = isCorrect
          ? 'Correct! +$points points'
          : 'Wrong guess. Next instrument!';
      return isCorrect;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearGuessResult() {
    _guessResult = null;
    notifyListeners();
  }
}
