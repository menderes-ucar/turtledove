class AnalyticsSummary {
  final int totalQuestions;
  final int correct;
  final int wrong;
  final int blank;
  final int tests;
  final double success;
  final double net;

  const AnalyticsSummary({
    required this.totalQuestions,
    required this.correct,
    required this.wrong,
    required this.blank,
    required this.tests,
    required this.success,
    required this.net,
  });
}
