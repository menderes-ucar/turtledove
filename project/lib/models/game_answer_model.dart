class GameAnswer {
  final String roundId;
  final String userId;
  final String answer;
  final DateTime answeredAt;

  const GameAnswer({
    required this.roundId,
    required this.userId,
    required this.answer,
    required this.answeredAt,
  });

  factory GameAnswer.fromMap(Map<String, dynamic> map) {
    return GameAnswer(
      roundId: map['round_id'] as String,
      userId: map['user_id'] as String,
      answer: (map['answer'] ?? '').toString(),
      answeredAt: DateTime.tryParse(map['answered_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
