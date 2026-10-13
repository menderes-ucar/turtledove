import '../../domain/entities/quiz_session.dart';
class QuizSessionModel extends QuizSession {
  const QuizSessionModel( {
    required super.sessionId,
    required super.questionIds,
    required super.isTimed,
    super.timeLimitSeconds,
    super.startedAt,
  });
  factory QuizSessionModel.fromJson(Map<String, dynamic> json) => QuizSessionModel(
  sessionId: json['session_id'] as String,
  questionIds: List<String>.from(json['question_ids'] as List? ?? const []),
  isTimed: json['is_timed'] as bool? ?? true,
  timeLimitSeconds: (json['time_limit_seconds'] as num?)?.toInt(),
  startedAt: json['started_at'] == null ? null : DateTime.tryParse(json['started_at'].toString()),
  );
}
