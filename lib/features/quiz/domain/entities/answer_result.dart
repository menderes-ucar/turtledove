class AnswerResult {
  final String answerId;
  final bool isCorrect;
  final String correctOption;
  final String explanation;
  const AnswerResult( {
    required this.answerId,
    required this.isCorrect,
    required this.correctOption,
    required this.explanation,
  });
}
