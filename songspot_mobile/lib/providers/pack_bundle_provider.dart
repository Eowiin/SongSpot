import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/pack_bundle.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class PackBundleProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final Uuid _uuid = const Uuid();

  PackBundleSession? _session;
  List<Stem> _stems = [];
  List<PackBundleLeaderboardEntry> _leaderboard = [];
  List<Message> _messages = [];
  String _stemsStatus = 'ready';
  bool _isLoading = false;
  String? _errorMessage;
  String? _guessResult;
  Map<String, String> _hintValues = {};
  String? _loadedPackId;

  PackBundleSession? get session => _session;
  List<Stem> get stems => _stems;
  String get stemsStatus => _stemsStatus;
  List<PackBundleLeaderboardEntry> get leaderboard => _leaderboard;
  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get guessResult => _guessResult;
  Map<String, String> get hintValues => _hintValues;
  String? get loadedPackId => _loadedPackId;

  void _applySessionResponse(Map<String, dynamic> response) {
    _session = PackBundleSession.fromJson(
      response['session'] as Map<String, dynamic>,
    );
    _stems = (response['stems'] as List)
        .map((item) => Stem.fromJson(item as Map<String, dynamic>))
        .toList();
    _stemsStatus = response['stems_status'] as String? ?? 'ready';
  }

  Future<void> loadSession({
    required String roomId,
    required String packId,
  }) async {
    // If switching to a different pack, clear stale state so loading skeleton shows.
    if (_loadedPackId != packId) {
      _session = null;
      _hintValues = {};
      _loadedPackId = null;
    }

    _isLoading = true;
    _errorMessage = null;
    _guessResult = null;
    notifyListeners();

    try {
      final response = await _apiService.getPackBundle(
        roomId: roomId,
        packId: packId,
      );
      final newSession = PackBundleSession.fromJson(
        response['session'] as Map<String, dynamic>,
      );
      final newStems = (response['stems'] as List)
          .map((item) => Stem.fromJson(item as Map<String, dynamic>))
          .toList();
      final newStemsStatus = response['stems_status'] as String? ?? 'ready';

      // Restore previously purchased hints into a local map first.
      final cachedHintValues = Map<String, String>.from(_hintValues);
      final newHintValues = <String, String>{};
      for (final hintType in newSession.hintsUsed) {
        final cachedValue = cachedHintValues[hintType];
        if (cachedValue != null) {
          newHintValues[hintType] = cachedValue;
          continue;
        }
        try {
          final hintResponse = await _apiService.purchasePackBundleHint(
            roomId: roomId,
            packId: packId,
            hintType: hintType,
          );
          newHintValues[hintType] = hintResponse['hint_value'] as String;
        } catch (_) {
          // Ignore errors restoring individual hints
        }
      }

      // Atomic swap — no intermediate state is ever rendered.
      _session = newSession;
      _stems = newStems;
      _stemsStatus = newStemsStatus;
      _hintValues = newHintValues;
      _loadedPackId = packId;
    } catch (e) {
      _errorMessage = e.toString();
      _hintValues = {};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> purchaseHint({
    required String roomId,
    required String packId,
    required String hintType,
  }) async {
    final response = await _apiService.purchasePackBundleHint(
      roomId: roomId,
      packId: packId,
      hintType: hintType,
    );
    _hintValues[hintType] = response['hint_value'] as String;
    if (_session != null && !_session!.hintsUsed.contains(hintType)) {
      _session = PackBundleSession(
        id: _session!.id,
        currentStage: _session!.currentStage,
        pointsEarned: _session!.pointsEarned,
        completedAt: _session!.completedAt,
        createdAt: _session!.createdAt,
        packTrack: _session!.packTrack,
        date: _session!.date,
        hintsUsed: [..._session!.hintsUsed, hintType],
      );
    }
    notifyListeners();
    return response;
  }

  Future<void> loadLeaderboard({
    required String roomId,
    required String packId,
  }) async {
    try {
      _errorMessage = null;
      final response = await _apiService.getPackBundleLeaderboard(
        roomId: roomId,
        packId: packId,
      );
      _leaderboard = (response['leaderboard'] as List)
          .map(
            (entry) => PackBundleLeaderboardEntry.fromJson(
              entry as Map<String, dynamic>,
            ),
          )
          .toList();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> loadMessages({
    required String roomId,
    required String packId,
  }) async {
    try {
      _errorMessage = null;
      final response = await _apiService.getPackBundleMessages(
        roomId: roomId,
        packId: packId,
      );
      final serverMessages = (response['messages'] as List)
          .map((item) => Message.fromJson(item as Map<String, dynamic>))
          .toList();
      _messages = _mergeServerMessages(serverMessages);
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> skipStage({
    required String roomId,
    required String packId,
  }) async {
    if (_session == null) return;
    try {
      _isLoading = true;
      _errorMessage = null;
      _guessResult = null;
      notifyListeners();

      final response = await _apiService.skipPackBundle(
        roomId: roomId,
        packId: packId,
      );
      _applySessionResponse(response);
      if (_session?.isCompleted == true) {
        await loadLeaderboard(roomId: roomId, packId: packId);
        await loadMessages(roomId: roomId, packId: packId);
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> submitGuess({
    required String roomId,
    required String packId,
    required String trackId,
  }) async {
    if (_session == null) return null;
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

      _applySessionResponse(response);
      _guessResult = response['message'] as String?;
      if (_session?.isCompleted == true) {
        await loadLeaderboard(roomId: roomId, packId: packId);
        await loadMessages(roomId: roomId, packId: packId);
      }
      return response;
    } catch (e) {
      _errorMessage = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> activateRetry({
    required String roomId,
    required String packId,
    required String action,
  }) async {
    if (_session == null) return null;

    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response = await _apiService.activatePackBundleRetry(
        roomId: roomId,
        packId: packId,
        action: action,
      );

      _applySessionResponse(response);
      _guessResult = response['message'] as String?;
      if (_session?.isCompleted == true) {
        await loadLeaderboard(roomId: roomId, packId: packId);
        await loadMessages(roomId: roomId, packId: packId);
      }
      return response;
    } catch (e) {
      _errorMessage = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearGuessResult() {
    _guessResult = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> sendMessage({
    required String roomId,
    required String packId,
    required String message,
    required User currentUser,
    String? clientMessageId,
  }) async {
    final resolvedClientMessageId = clientMessageId ?? _uuid.v4();
    _upsertLocalMessage(
      Message.pending(
        clientMessageId: resolvedClientMessageId,
        user: currentUser,
        message: message,
      ),
    );
    notifyListeners();

    try {
      final response = await _apiService.sendPackBundleMessage(
        roomId: roomId,
        packId: packId,
        message: message,
        clientMessageId: resolvedClientMessageId,
      );
      _reconcileIncomingMessage(Message.fromJson(response));
    } catch (e) {
      _errorMessage = e.toString();
      _markMessageFailed(resolvedClientMessageId, _errorMessage!);
    }
  }

  Future<void> retryMessage({
    required String roomId,
    required String packId,
    required Message message,
    required User currentUser,
  }) async {
    final clientMessageId = message.clientMessageId;
    if (clientMessageId == null) return;

    _upsertLocalMessage(
      message.copyWith(
        user: currentUser,
        deliveryStatus: MessageDeliveryStatus.sending,
        clearFailureReason: true,
      ),
    );
    notifyListeners();

    await sendMessage(
      roomId: roomId,
      packId: packId,
      message: message.message,
      currentUser: currentUser,
      clientMessageId: clientMessageId,
    );
  }

  List<Message> _mergeServerMessages(List<Message> serverMessages) {
    final unresolvedMessages = _messages.where((message) {
      if (!message.isSending && !message.isFailed) {
        return false;
      }

      return !serverMessages.any(
        (serverMessage) =>
            serverMessage.id == message.id ||
            (message.clientMessageId != null &&
                serverMessage.clientMessageId == message.clientMessageId),
      );
    }).toList();

    return [...unresolvedMessages, ...serverMessages];
  }

  void _upsertLocalMessage(Message message) {
    final existingIndex = _messages.indexWhere(
      (existingMessage) =>
          existingMessage.id == message.id ||
          (message.clientMessageId != null &&
              existingMessage.clientMessageId == message.clientMessageId),
    );

    if (existingIndex >= 0) {
      _messages[existingIndex] = message;
      return;
    }

    _messages.insert(0, message);
  }

  void _reconcileIncomingMessage(Message message) {
    final existingIndex = _messages.indexWhere(
      (existingMessage) =>
          existingMessage.id == message.id ||
          (message.clientMessageId != null &&
              existingMessage.clientMessageId == message.clientMessageId),
    );
    final resolvedMessage = message.copyWith(
      deliveryStatus: MessageDeliveryStatus.sent,
      clearFailureReason: true,
    );

    if (existingIndex >= 0) {
      _messages[existingIndex] = resolvedMessage;
    } else {
      _messages.insert(0, resolvedMessage);
    }
    notifyListeners();
  }

  void _markMessageFailed(String clientMessageId, String errorMessage) {
    final existingIndex = _messages.indexWhere(
      (message) => message.clientMessageId == clientMessageId,
    );
    if (existingIndex < 0) {
      return;
    }

    _messages[existingIndex] = _messages[existingIndex].copyWith(
      deliveryStatus: MessageDeliveryStatus.failed,
      failureReason: errorMessage,
    );
    notifyListeners();
  }

  void clearMessages() {
    _messages = [];
    notifyListeners();
  }
}
