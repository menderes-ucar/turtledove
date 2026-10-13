class UserAnswer {
  final String id;
  final String userId;
  final String questionId;
  final String quizAttemptId;
  final String? selectedOption;
  final bool? isCorrect;
  final int? timeSpentSeconds;
  final DateTime answeredAt;
  const UserAnswer( {
    required this.id,
    required this.userId,
    required this.questionId,
    required this.quizAttemptId,
    this.selectedOption,
    this.isCorrect,
    this.timeSpentSeconds,
    required this.answeredAt,
  });
  bool get isBlank => selectedOption == null;
  bool get isWrong => isCorrect == false;
}
