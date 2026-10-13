import '../entities/quiz_session.dart';
import '../repositories/quiz_repository.dart';
class StartQuiz {
  final QuizRepository repository;
  const StartQuiz(this.repository);
  Future<QuizSession> call( {
    required String subjectId,
    int questionCount = 20,
    bool isTimed = true,
    int timeLimitSeconds = 1800,
    bool fromErrorNotebook = false,
  }) => repository.startSession(
  subjectId: subjectId,
  questionCount: questionCount,
  isTimed: isTimed,
  timeLimitSeconds: timeLimitSeconds,
  fromErrorNotebook: fromErrorNotebook,
  );
}
