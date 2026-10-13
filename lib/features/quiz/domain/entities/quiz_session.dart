class QuizSession {
  final String sessionId;
  final List<String> questionIds;
  final bool isTimed;
  final int? timeLimitSeconds;
  final DateTime? startedAt;
  const QuizSession( {
    required this.sessionId,
    required this.questionIds,
    required this.isTimed,
    this.timeLimitSeconds,
    this.startedAt,
  });
}
