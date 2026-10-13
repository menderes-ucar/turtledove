class WordGameState {
  final String sessionId;
  final String languageCode;
  final String requiredLetter;
  final String turnUserId;
  final int turnNumber;
  final String? lastWord;
  final DateTime? turnStartedAt;
  final DateTime? turnDeadlineAt;
  final String status;
  final String? winnerUserId;
  final String? loserUserId;
  final String? endReason;
  final String? lastError;
  final String? lastErrorUserId;

  const WordGameState({
    required this.sessionId,
    required this.languageCode,
    required this.requiredLetter,
    required this.turnUserId,
    required this.turnNumber,
    required this.lastWord,
    required this.turnStartedAt,
    required this.turnDeadlineAt,
    required this.status,
    required this.winnerUserId,
    required this.loserUserId,
    required this.endReason,
    required this.lastError,
    required this.lastErrorUserId,
  });

  factory WordGameState.fromMap(Map<String, dynamic> map) {
    return WordGameState(
      sessionId: map['session_id']?.toString() ?? '',
      languageCode: map['language_code']?.toString() ?? 'en',
      requiredLetter: map['required_letter']?.toString() ?? '',
      turnUserId: map['turn_user_id']?.toString() ?? '',
      turnNumber: (map['turn_number'] as num?)?.toInt() ?? 0,
      lastWord: map['last_word']?.toString(),
      turnStartedAt: DateTime.tryParse(map['turn_started_at']?.toString() ?? ''),
      turnDeadlineAt: DateTime.tryParse(map['turn_deadline_at']?.toString() ?? ''),
      status: map['status']?.toString() ?? 'waiting',
      winnerUserId: map['winner_user_id']?.toString(),
      loserUserId: map['loser_user_id']?.toString(),
      endReason: map['end_reason']?.toString(),
      lastError: map['last_error']?.toString(),
      lastErrorUserId: map['last_error_user_id']?.toString(),
    );
  }

  bool get isPlaying => status == 'playing';
  bool get isCompleted => status == 'completed';
}

class WordGamePlay {
  final String id;
  final String sessionId;
  final String userId;
  final int turnNumber;
  final String word;
  final String normalizedWord;
  final String firstLetter;
  final String lastLetter;
  final int points;
  final DateTime createdAt;

  const WordGamePlay({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.turnNumber,
    required this.word,
    required this.normalizedWord,
    required this.firstLetter,
    required this.lastLetter,
    required this.points,
    required this.createdAt,
  });

  factory WordGamePlay.fromMap(Map<String, dynamic> map) {
    return WordGamePlay(
      id: map['id']?.toString() ?? '',
      sessionId: map['session_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      turnNumber: (map['turn_number'] as num?)?.toInt() ?? 0,
      word: map['word']?.toString() ?? '',
      normalizedWord: map['normalized_word']?.toString() ?? '',
      firstLetter: map['first_letter']?.toString() ?? '',
      lastLetter: map['last_letter']?.toString() ?? '',
      points: (map['points'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
