class HistoryTrack {
  final String id;
  final String title;
  final String artist;
  final String? coverUrl;
  final String? previewUrl;

  const HistoryTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.coverUrl,
    this.previewUrl,
  });

  factory HistoryTrack.fromJson(Map<String, dynamic> json) {
    return HistoryTrack(
      id: json['id'].toString(),
      title: json['title'] as String,
      artist: json['artist'] as String,
      coverUrl: json['cover_url'] as String?,
      previewUrl: json['preview_url'] as String?,
    );
  }
}

class HistorySession {
  final bool correctGuess;
  final int? pointsEarned;
  final int currentSnippet;
  final int guessesMade;
  final DateTime? completedAt;

  const HistorySession({
    required this.correctGuess,
    this.pointsEarned,
    required this.currentSnippet,
    required this.guessesMade,
    this.completedAt,
  });

  factory HistorySession.fromJson(Map<String, dynamic> json) {
    return HistorySession(
      correctGuess: json['correct_guess'] as bool,
      pointsEarned: json['points_earned'] as int?,
      currentSnippet: json['current_snippet'] as int,
      guessesMade: json['guesses_made'] as int,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
    );
  }
}

/// Summary entry for the history list screen.
class HistoryDay {
  final String date;
  final HistoryTrack track;
  final HistorySession? mySession;

  const HistoryDay({
    required this.date,
    required this.track,
    this.mySession,
  });

  factory HistoryDay.fromJson(Map<String, dynamic> json) {
    return HistoryDay(
      date: json['date'] as String,
      track: HistoryTrack.fromJson(json['track'] as Map<String, dynamic>),
      mySession: json['my_session'] != null
          ? HistorySession.fromJson(json['my_session'] as Map<String, dynamic>)
          : null,
    );
  }
}

class HistoryLeaderboardEntry {
  final String userId;
  final String username;
  final int pointsEarned;
  final int snippetNumber;
  final DateTime? completedAt;

  const HistoryLeaderboardEntry({
    required this.userId,
    required this.username,
    required this.pointsEarned,
    required this.snippetNumber,
    this.completedAt,
  });

  factory HistoryLeaderboardEntry.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return HistoryLeaderboardEntry(
      userId: user['id'].toString(),
      username: user['username'] as String,
      pointsEarned: json['points_earned'] as int,
      snippetNumber: json['snippet_number'] as int,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
    );
  }
}

class HistoryMessage {
  final String id;
  final String userId;
  final String username;
  final String message;
  final DateTime createdAt;

  const HistoryMessage({
    required this.id,
    required this.userId,
    required this.username,
    required this.message,
    required this.createdAt,
  });

  factory HistoryMessage.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return HistoryMessage(
      id: json['id'].toString(),
      userId: user['id'].toString(),
      username: user['username'] as String,
      message: json['message'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Full detail entry for a specific past day.
class HistoryDayDetail {
  final String date;
  final HistoryTrack track;
  final HistorySession? mySession;
  final List<HistoryLeaderboardEntry> leaderboard;
  final List<HistoryMessage> messages;

  const HistoryDayDetail({
    required this.date,
    required this.track,
    this.mySession,
    required this.leaderboard,
    required this.messages,
  });

  factory HistoryDayDetail.fromJson(Map<String, dynamic> json) {
    return HistoryDayDetail(
      date: json['date'] as String,
      track: HistoryTrack.fromJson(json['track'] as Map<String, dynamic>),
      mySession: json['my_session'] != null
          ? HistorySession.fromJson(json['my_session'] as Map<String, dynamic>)
          : null,
      leaderboard: (json['leaderboard'] as List<dynamic>)
          .map((e) => HistoryLeaderboardEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      messages: (json['messages'] as List<dynamic>)
          .map((e) => HistoryMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
