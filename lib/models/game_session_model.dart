class GameSession {
  final String id;
  final String gameType;
  final String status;
  final String createdBy;
  final int currentRound;
  final int totalRounds;
  final List<String> categories;
  final String? category;
  final String? subcategory;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GameSession({
    required this.id,
    required this.gameType,
    required this.status,
    required this.createdBy,
    required this.currentRound,
    required this.totalRounds,
    required this.categories,
    required this.category,
    required this.subcategory,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GameSession.fromMap(Map<String, dynamic> map) {
    return GameSession(
      id: map['id'] as String,
      gameType: (map['game_type'] ?? '') as String,
      status: (map['status'] ?? 'waiting') as String,
      createdBy: map['created_by'] as String,
      currentRound: (map['current_round'] as num?)?.toInt() ?? 0,
      totalRounds: (map['total_rounds'] as num?)?.toInt() ?? 0,
      categories: _parseCategories(map['categories']),
      category: map['category']?.toString(),
      subcategory: map['subcategory']?.toString(),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  bool get isWaiting => status == 'waiting';
  bool get isPlaying => status == 'playing';
  bool get isCompleted => status == 'completed';
}

List<String> _parseCategories(dynamic raw) {
  if (raw is List) {
    return raw
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

class GamePlayer {
  final String sessionId;
  final String userId;
  final int score;
  final bool ready;
  final int mistakes;
  final bool surrendered;
  final DateTime joinedAt;
  final bool roundConfirmed;

  const GamePlayer({
    required this.sessionId,
    required this.userId,
    required this.score,
    required this.ready,
    required this.mistakes,
    required this.surrendered,
    required this.joinedAt,
    required this.roundConfirmed,
  });

  factory GamePlayer.fromMap(Map<String, dynamic> map) {
    return GamePlayer(
      sessionId: map['session_id'] as String,
      userId: map['user_id'] as String,
      score: (map['score'] as num?)?.toInt() ?? 0,
      ready: map['ready'] as bool? ?? false,
      mistakes: (map['mistakes'] as num?)?.toInt() ?? 0,
      surrendered: map['surrendered'] as bool? ?? false,
      joinedAt: DateTime.tryParse(map['joined_at']?.toString() ?? '') ?? DateTime.now(),
      roundConfirmed: map['round_confirmed'] == true,
    );
  }
}

class GameRound {
  final String id;
  final String sessionId;
  final int roundNumber;
  final String questionId;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const GameRound({
    required this.id,
    required this.sessionId,
    required this.roundNumber,
    required this.questionId,
    required this.createdAt,
    required this.resolvedAt,
  });

  factory GameRound.fromMap(Map<String, dynamic> map) {
    return GameRound(
      id: map['id'] as String,
      sessionId: map['session_id'] as String,
      roundNumber: (map['round_number'] as num?)?.toInt() ?? 0,
      questionId: map['question_id'] as String,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      resolvedAt: DateTime.tryParse(map['resolved_at']?.toString() ?? ''),
    );
  }
}
