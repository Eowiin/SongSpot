import 'package:flutter/foundation.dart';
import '../models/game_score.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class StatsProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final StorageService _storage = StorageService();

  UserBest _userBest = UserBest.empty;
  List<GameScore> _leaderboard = [];
  bool _isLoadingStats = false;
  bool _isLoadingLeaderboard = false;
  String? _statsError;
  String? _leaderboardError;
  String _leaderboardTimeframe = 'daily';
  String? _leaderboardCategoryId;

  UserBest get userBest => _userBest;
  List<GameScore> get leaderboard => _leaderboard;
  bool get isLoadingStats => _isLoadingStats;
  bool get isLoadingLeaderboard => _isLoadingLeaderboard;
  String? get statsError => _statsError;
  String? get leaderboardError => _leaderboardError;
  String get leaderboardTimeframe => _leaderboardTimeframe;
  String? get leaderboardCategoryId => _leaderboardCategoryId;

  Future<void> loadStats({bool isGuest = false}) async {
    _isLoadingStats = true;
    _statsError = null;
    notifyListeners();
    try {
      if (isGuest) {
        final raw = await _storage.getGuestStats();
        _userBest = UserBest(
          bestScoreOverall: raw['best_score']!,
          bestStreakOverall: raw['best_streak']!,
          totalSongsPlayed: raw['songs_played']!,
          totalSongsCorrect: raw['songs_correct']!,
          perCategory: {},
        );
      } else {
        final data = await _api.getUserStats();
        _userBest = UserBest.fromJson(data);
      }
    } catch (e) {
      _statsError = e.toString();
    } finally {
      _isLoadingStats = false;
      notifyListeners();
    }
  }

  Future<void> loadLeaderboard({
    String timeframe = 'daily',
    String? categoryId,
  }) async {
    _leaderboardTimeframe = timeframe;
    _leaderboardCategoryId = categoryId;
    _isLoadingLeaderboard = true;
    _leaderboardError = null;
    notifyListeners();
    try {
      final results = await _api.getLeaderboard(
        timeframe: timeframe,
        categoryId: categoryId,
        limit: 50,
      );
      _leaderboard = results
          .map((j) => GameScore.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _leaderboardError = e.toString();
    } finally {
      _isLoadingLeaderboard = false;
      notifyListeners();
    }
  }
}
