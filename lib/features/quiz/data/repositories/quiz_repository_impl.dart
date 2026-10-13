import '../../domain/entities/answer_result.dart';
import '../../domain/entities/question.dart';
import '../../domain/entities/quiz_result.dart';
import '../../domain/entities/quiz_session.dart';
import '../../domain/repositories/quiz_repository.dart';
import '../datasources/quiz_remote_datasource.dart';
class QuizRepositoryImpl implements QuizRepository {
  final QuizRemoteDataSource remote;
  const QuizRepositoryImpl(this.remote);
  @override
  Future<QuizSession> startSession( {
    required String subjectId,
    required int questionCount,
    required bool isTimed,
    required int timeLimitSeconds,
    bool fromErrorNotebook = false,
  }) => remote.startSession(
  subjectId: subjectId,
  questionCount: questionCount,
  isTimed: isTimed,
  timeLimitSeconds: timeLimitSeconds,
  fromErrorNotebook: fromErrorNotebook,
  );
  @override
  Future<List<Question>> getQuestions(String sessionId) => remote.getQuestions(sessionId);
  @override
  Future<AnswerResult> submitAnswer( {
    required String sessionId, required String questionId, required String selectedOption
  }) async {
    final r = await remote.submitAnswer(sessionId: sessionId, questionId: questionId, selectedOption: selectedOption);
    return AnswerResult(
    answerId: r['answer_id'] as String,
    isCorrect: r['is_correct'] == true,
    correctOption: (r['correct_option'] as String).toUpperCase(),
    explanation: r['explanation'] as String? ?? '',
    );
  }
  @override
  Future<QuizResult> completeSession(String sessionId) async {
    final r = await remote.completeSession(sessionId);
    return QuizResult(
    correctAnswers: (r['correct_answers'] as num).toInt(),
    wrongAnswers: (r['wrong_answers'] as num).toInt(),
    blankAnswers: (r['blank_answers'] as num).toInt(),
    durationSeconds: (r['duration_seconds'] as num).toInt(),
    net: (r['net'] as num).toDouble(),
    );
  }
  @override
  Future<void> abandonSession(String sessionId) => remote.abandonSession(sessionId);
}
