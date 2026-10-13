import 'quiz_status.dart';
class QuizAttempt {
  final String id;
  final String userId;
  final String subjectId;
  final QuizStatus status;
  final int totalQuestions;
  final int correctAnswers;
  final int wrongAnswers;
  final int blankAnswers;
  final int durationSeconds;
  final double? score;
  final bool isTimed;
  final int? timeLimitSeconds;
  final DateTime startedAt;
  final DateTime? completedAt;
  const QuizAttempt( {
    required this.id,
    required this.userId,
    required this.subjectId,
    required this.status,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.wrongAnswers,
    required this.blankAnswers,
    required this.durationSeconds,
    this.score,
    required this.isTimed,
    this.timeLimitSeconds,
    required this.startedAt,
    this.completedAt,
  });
  double get successPercentage => totalQuestions == 0 ? 0 : (correctAnswers / totalQuestions) * 100;
  bool get isRunning => status == QuizStatus.running;
  bool get isCompleted => status == QuizStatus.completed;
  int get averageTimePerQuestion => totalQuestions == 0 ? 0 : (durationSeconds / totalQuestions).round();
  QuizAttempt copyWith( {
    QuizStatus? status, int? correctAnswers, int? wrongAnswers, int? blankAnswers,
    int? durationSeconds, double? score, DateTime? completedAt,
  }) => QuizAttempt(
  id: id, userId: userId, subjectId: subjectId,
  status: status ?? this.status,
  totalQuestions: totalQuestions,
  correctAnswers: correctAnswers ?? this.correctAnswers,
  wrongAnswers: wrongAnswers ?? this.wrongAnswers,
  blankAnswers: blankAnswers ?? this.blankAnswers,
  durationSeconds: durationSeconds ?? this.durationSeconds,
  score: score ?? this.score,
  isTimed: isTimed, timeLimitSeconds: timeLimitSeconds,
  startedAt: startedAt, completedAt: completedAt ?? this.completedAt,
  );
}
