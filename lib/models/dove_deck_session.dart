class DoveDeckSession {
  final String id;
  final String playerOne;
  final String playerTwo;
  final String status;
  final Map<String, dynamic> state;
  final int version;
  final String currentTurn;
  final String? winner;
  final bool playerOneReady;
  final bool playerTwoReady;

  const DoveDeckSession({
    required this.id,
    required this.playerOne,
    required this.playerTwo,
    required this.status,
    required this.state,
    required this.version,
    required this.currentTurn,
    required this.winner,
    this.playerOneReady = false,
    this.playerTwoReady = false,
  });

  factory DoveDeckSession.fromMap(Map<String, dynamic> row) => DoveDeckSession(
    id: row['id'].toString(),
    playerOne: row['player_one'].toString(),
    playerTwo: row['player_two'].toString(),
    status: row['status']?.toString() ?? 'waiting',
    state: row['state'] is Map ? Map<String, dynamic>.from(row['state'] as Map) : const {},
    version: (row['version'] as num?)?.toInt() ?? 0,
    currentTurn: row['current_turn']?.toString() ?? '',
    winner: row['winner']?.toString(),
    playerOneReady: row['player_one_ready'] == true,
    playerTwoReady: row['player_two_ready'] == true,
  );

  bool get isWaiting => status == 'waiting';
  bool get isPlaying => status == 'playing';
  bool get isFinished => status == 'finished';
  bool get bothReady => playerOneReady && playerTwoReady;
  bool isReady(String userId) =>
      userId == playerOne ? playerOneReady :
      userId == playerTwo ? playerTwoReady : false;
}
