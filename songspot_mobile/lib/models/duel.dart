class DuelOpponent {
  final String username;
  final int elo;

  const DuelOpponent({required this.username, required this.elo});

  factory DuelOpponent.fromJson(Map<String, dynamic> j) => DuelOpponent(
        username: j['username'] as String,
        elo: (j['elo'] as num).toInt(),
      );
}

class DuelPlaylist {
  final String id;
  final String name;

  const DuelPlaylist({required this.id, required this.name});

  factory DuelPlaylist.fromJson(Map<String, dynamic> j) => DuelPlaylist(
        id: j['id'] as String,
        name: j['name'] as String,
      );
}

class DuelTrack {
  final String id;
  final String previewUrl;
  final String coverUrl;
  // Filled in after round_result
  final String? title;
  final String? artist;

  const DuelTrack({
    required this.id,
    required this.previewUrl,
    required this.coverUrl,
    this.title,
    this.artist,
  });

  factory DuelTrack.fromRoundStart(Map<String, dynamic> j) => DuelTrack(
        id: j['id'] as String? ?? '',
        previewUrl: j['preview_url'] as String? ?? '',
        coverUrl: j['cover_url'] as String? ?? '',
      );

  factory DuelTrack.fromRoundResult(Map<String, dynamic> j) => DuelTrack(
        id: '',
        previewUrl: '',
        coverUrl: j['cover_url'] as String? ?? '',
        title: j['title'] as String?,
        artist: j['artist'] as String?,
      );
}

class DuelPlayerResult {
  final bool correct;
  final int points;
  final int snippetsUsed;

  const DuelPlayerResult({
    required this.correct,
    required this.points,
    required this.snippetsUsed,
  });

  factory DuelPlayerResult.fromJson(Map<String, dynamic> j) => DuelPlayerResult(
        correct: j['correct'] as bool? ?? false,
        points: (j['points'] as num?)?.toInt() ?? 0,
        snippetsUsed: (j['snippets_used'] as num?)?.toInt() ?? 0,
      );
}

class DuelRoundResult {
  final int round;
  final DuelTrack track;
  final DuelPlayerResult player;
  final DuelPlayerResult opponent;
  final int playerScore;
  final int opponentScore;

  const DuelRoundResult({
    required this.round,
    required this.track,
    required this.player,
    required this.opponent,
    required this.playerScore,
    required this.opponentScore,
  });

  factory DuelRoundResult.fromJson(Map<String, dynamic> j) => DuelRoundResult(
        round: (j['round'] as num).toInt(),
        track: DuelTrack.fromRoundResult(j['track'] as Map<String, dynamic>),
        player: DuelPlayerResult.fromJson(j['player'] as Map<String, dynamic>),
        opponent: DuelPlayerResult.fromJson(j['opponent'] as Map<String, dynamic>),
        playerScore: (j['scores']?['player'] as num?)?.toInt() ?? 0,
        opponentScore: (j['scores']?['opponent'] as num?)?.toInt() ?? 0,
      );
}

class DuelMatchEnd {
  final String winner; // 'player' | 'opponent' | 'draw'
  final int playerFinalScore;
  final int opponentFinalScore;
  final int eloChange;
  final int newElo;

  const DuelMatchEnd({
    required this.winner,
    required this.playerFinalScore,
    required this.opponentFinalScore,
    required this.eloChange,
    required this.newElo,
  });

  factory DuelMatchEnd.fromJson(Map<String, dynamic> j) => DuelMatchEnd(
        winner: j['winner'] as String,
        playerFinalScore: (j['final_scores']?['player'] as num?)?.toInt() ?? 0,
        opponentFinalScore: (j['final_scores']?['opponent'] as num?)?.toInt() ?? 0,
        eloChange: (j['elo_change']?['player'] as num?)?.toInt() ?? 0,
        newElo: (j['new_elo']?['player'] as num?)?.toInt() ?? 0,
      );
}

class UserElo {
  final int elo;
  final int wins;
  final int losses;
  final int draws;
  final int rank;

  const UserElo({
    required this.elo,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.rank,
  });

  factory UserElo.fromJson(Map<String, dynamic> j) => UserElo(
        elo: (j['elo'] as num).toInt(),
        wins: (j['wins'] as num?)?.toInt() ?? 0,
        losses: (j['losses'] as num?)?.toInt() ?? 0,
        draws: (j['draws'] as num?)?.toInt() ?? 0,
        rank: (j['rank'] as num?)?.toInt() ?? 0,
      );
}
