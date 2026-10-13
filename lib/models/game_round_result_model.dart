class GameRoundResult {
  final String userId;
  final String answer;
  final bool? isCorrect;
  final int points;

  const GameRoundResult({
    required this.userId,
    required this.answer,
    required this.isCorrect,
    required this.points,
  });

  factory GameRoundResult.fromMap(Map<String, dynamic> map) {
    return GameRoundResult(
      userId: map['user_id'] as String,
      answer: (map['answer'] ?? '').toString(),
      isCorrect: map['is_correct'] as bool?,
      points: (map['points'] as num?)?.toInt() ?? 0,
    );
  }
}
