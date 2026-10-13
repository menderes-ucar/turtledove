import '../entities/answer_result.dart';
import '../repositories/quiz_repository.dart';
class SubmitQuizAnswer {
  final QuizRepository repository;
  const SubmitQuizAnswer(this.repository);
  Future<AnswerResult> call( {
    required String sessionId, required String questionId, required String selectedOption
  }) =>
  repository.submitAnswer(sessionId: sessionId, questionId: questionId, selectedOption: selectedOption);
}
