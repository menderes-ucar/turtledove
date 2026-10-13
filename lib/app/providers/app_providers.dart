import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/analytics/data/datasources/analytics_remote_datasource.dart';
import '../../features/analytics/data/repositories/analytics_repository_impl.dart';
import '../../features/analytics/presentation/providers/analytics_provider.dart';
import '../../features/auth/data/datasources/auth_remote_datasource.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/error_notebook/data/datasources/error_notebook_remote_datasource.dart';
import '../../features/error_notebook/data/repositories/error_notebook_repository_impl.dart';
import '../../features/error_notebook/presentation/providers/error_notebook_provider.dart';
import '../../features/notes/data/datasources/notes_remote_datasource.dart';
import '../../features/notes/data/repositories/notes_repository_impl.dart';
import '../../features/notes/presentation/providers/notes_provider.dart';
import '../../features/quiz/data/datasources/quiz_remote_datasource.dart';
import '../../features/quiz/data/repositories/quiz_repository_impl.dart';
import '../../features/quiz/domain/usecases/abandon_quiz.dart';
import '../../features/quiz/domain/usecases/complete_quiz.dart';
import '../../features/quiz/domain/usecases/get_quiz_questions.dart';
import '../../features/quiz/domain/usecases/start_quiz.dart';
import '../../features/quiz/domain/usecases/submit_quiz_answer.dart';
import '../../features/quiz/presentation/providers/quiz_provider.dart';
import '../../features/subjects/data/datasources/subjects_remote_datasource.dart';
import '../../features/subjects/data/repositories/subjects_repository_impl.dart';
import '../../features/subjects/domain/usecases/get_subjects.dart';
import '../../features/subjects/presentation/providers/subjects_provider.dart';

class AppProviders {
  const AppProviders._();

  static List<SingleChildWidget> create(SupabaseClient client) {
    final authRepository = AuthRepositoryImpl(
      AuthRemoteDataSource(client),
    );

    final subjectsRepository = SubjectsRepositoryImpl(
      SubjectsRemoteDataSource(client),
    );

    final notesRepository = NotesRepositoryImpl(
      NotesRemoteDataSource(client),
    );

    final errorNotebookRepository = ErrorNotebookRepositoryImpl(
      ErrorNotebookRemoteDataSource(client),
    );

    final analyticsRepository = AnalyticsRepositoryImpl(
      AnalyticsRemoteDataSource(client),
    );

    final quizRepository = QuizRepositoryImpl(
      QuizRemoteDataSource(client),
    );

    final startQuiz = StartQuiz(quizRepository);
    final getQuizQuestions = GetQuizQuestions(quizRepository);
    final submitQuizAnswer = SubmitQuizAnswer(quizRepository);
    final completeQuiz = CompleteQuiz(quizRepository);
    final abandonQuiz = AbandonQuiz(quizRepository);

    return <SingleChildWidget>[
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(authRepository),
      ),
      ChangeNotifierProvider<SubjectsProvider>(
        create: (_) => SubjectsProvider(
          GetSubjects(subjectsRepository),
        ),
      ),
      ChangeNotifierProvider<NotesProvider>(
        create: (_) => NotesProvider(notesRepository),
      ),
      ChangeNotifierProvider<ErrorNotebookProvider>(
        create: (_) => ErrorNotebookProvider(errorNotebookRepository),
      ),
      ChangeNotifierProvider<AnalyticsProvider>(
        create: (_) => AnalyticsProvider(analyticsRepository),
      ),
      ChangeNotifierProxyProvider<AuthProvider, QuizProvider>(
        create: (_) => QuizProvider(
          userId: '',
          startQuizUseCase: startQuiz,
          getQuizQuestionsUseCase: getQuizQuestions,
          submitQuizAnswerUseCase: submitQuizAnswer,
          completeQuizUseCase: completeQuiz,
          abandonQuizUseCase: abandonQuiz,
        ),
        update: (_, auth, quizProvider) {
          quizProvider ??= QuizProvider(
            userId: '',
            startQuizUseCase: startQuiz,
            getQuizQuestionsUseCase: getQuizQuestions,
            submitQuizAnswerUseCase: submitQuizAnswer,
            completeQuizUseCase: completeQuiz,
            abandonQuizUseCase: abandonQuiz,
          );

          quizProvider.setUserId(auth.user?.id);
          return quizProvider;
        },
      ),
    ];
  }
}
