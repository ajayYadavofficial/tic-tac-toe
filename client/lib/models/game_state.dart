class GameState {
  final List<String> board;     // 9 cells, "" / "X" / "O"
  final String turn;            // "X" or "O"
  final String status;          // "waiting" / "playing" / "game_over"
  final String playerX;         // user ID
  final String playerO;         // user ID
  final String playerXName;     // display name
  final String playerOName;     // display name
  final int turnSecs;           // 0 = no timer, >0 = seconds per turn
  final int turnStartedAt;      // unix timestamp (0 if no timer)

  const GameState({
    required this.board,
    required this.turn,
    required this.status,
    required this.playerX,
    required this.playerO,
    this.playerXName = '',
    this.playerOName = '',
    this.turnSecs = 0,
    this.turnStartedAt = 0,
  });

  factory GameState.initial() => const GameState(
        board: ['', '', '', '', '', '', '', '', ''],
        turn: 'X',
        status: 'waiting',
        playerX: '',
        playerO: '',
      );

  factory GameState.fromJson(Map<String, dynamic> json) => GameState(
        board: List<String>.from(json['board'] as List),
        turn: json['turn'] as String,
        status: json['status'] as String,
        playerX: json['player_x'] as String,
        playerO: json['player_o'] as String,
        playerXName: json['player_x_name'] as String? ?? '',
        playerOName: json['player_o_name'] as String? ?? '',
        turnSecs: (json['turn_secs'] as num?)?.toInt() ?? 0,
        turnStartedAt: (json['turn_started_at'] as num?)?.toInt() ?? 0,
      );
}

class GameResult {
  final String winner; // user ID or "" for draw
  final String result; // "win" or "draw"
  final List<String> board; // final board state
  final String playerX; // user ID
  final String playerO; // user ID
  final String playerXName; // display name
  final String playerOName; // display name

  const GameResult({
    required this.winner,
    required this.result,
    required this.board,
    required this.playerX,
    required this.playerO,
    this.playerXName = '',
    this.playerOName = '',
  });

  factory GameResult.fromJson(Map<String, dynamic> json) => GameResult(
        winner: json['winner'] as String? ?? '',
        result: json['result'] as String,
        board: List<String>.from(json['board'] as List? ?? List.filled(9, '')),
        playerX: json['player_x'] as String? ?? '',
        playerO: json['player_o'] as String? ?? '',
        playerXName: json['player_x_name'] as String? ?? '',
        playerOName: json['player_o_name'] as String? ?? '',
      );
}

class PlayerStats {
  final int wins;
  final int losses;
  final int draws;
  final int score;

  const PlayerStats({
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.score = 0,
  });

  factory PlayerStats.fromJson(Map<String, dynamic> json) => PlayerStats(
        wins: json['wins'] as int? ?? 0,
        losses: json['losses'] as int? ?? 0,
        draws: json['draws'] as int? ?? 0,
        score: json['score'] as int? ?? 0,
      );
}

class LeaderboardEntry {
  final String userId;
  final String username;
  final int score;
  final int rank;

  const LeaderboardEntry({
    required this.userId,
    required this.username,
    required this.score,
    required this.rank,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LeaderboardEntry(
        userId: json['user_id'] as String? ?? '',
        username: json['username'] as String? ?? '',
        score: (json['score'] as num?)?.toInt() ?? 0,
        rank: (json['rank'] as num?)?.toInt() ?? 0,
      );
}
