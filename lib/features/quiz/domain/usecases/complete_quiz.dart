import '../entities/quiz_result.dart';
import '../repositories/quiz_repository.dart';
class CompleteQuiz {
  final QuizRepository repository;
  const CompleteQuiz(this.repository);
  Future<QuizResult> call(String sessionId) => repository.completeSession(sessionId);
}
