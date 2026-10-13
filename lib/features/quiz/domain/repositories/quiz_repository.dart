import '../entities/answer_result.dart';
import '../entities/question.dart';
import '../entities/quiz_result.dart';
import '../entities/quiz_session.dart';
abstract interface class QuizRepository {
  Future<QuizSession> startSession( {
    required String subjectId,
    required int questionCount,
    required bool isTimed,
    required int timeLimitSeconds,
    bool fromErrorNotebook = false,
  });
  Future<List<Question>> getQuestions(String sessionId);
  Future<AnswerResult> submitAnswer( {
    required String sessionId,
    required String questionId,
    required String selectedOption,
  });
  Future<QuizResult> completeSession(String sessionId);
  Future<void> abandonSession(String sessionId);
}
