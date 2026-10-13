import '../repositories/quiz_repository.dart';
class AbandonQuiz {
  final QuizRepository repository;
  const AbandonQuiz(this.repository);
  Future<void> call(String sessionId) => repository.abandonSession(sessionId);
}
