import '../entities/question.dart';
import '../repositories/quiz_repository.dart';
class GetQuizQuestions {
  final QuizRepository repository;
  const GetQuizQuestions(this.repository);
  Future<List<Question>> call(String sessionId) => repository.getQuestions(sessionId);
}
