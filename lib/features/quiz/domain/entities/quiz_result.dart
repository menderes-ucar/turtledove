class QuizResult {
  final int correctAnswers;
  final int wrongAnswers;
  final int blankAnswers;
  final int durationSeconds;
  final double net;
  const QuizResult( {
    required this.correctAnswers,
    required this.wrongAnswers,
    required this.blankAnswers,
    required this.durationSeconds,
    required this.net,
  });
}
