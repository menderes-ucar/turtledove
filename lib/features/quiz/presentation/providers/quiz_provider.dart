import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/question.dart';
import '../../domain/entities/quiz_attempt.dart';
import '../../domain/entities/quiz_status.dart';
import '../../domain/entities/user_answer.dart';
import '../../domain/usecases/abandon_quiz.dart';
import '../../domain/usecases/complete_quiz.dart';
import '../../domain/usecases/get_quiz_questions.dart';
import '../../domain/usecases/start_quiz.dart';
import '../../domain/usecases/submit_quiz_answer.dart';

class QuizProvider extends ChangeNotifier {
  String userId;

  final StartQuiz startQuizUseCase;
  final GetQuizQuestions getQuizQuestionsUseCase;
  final SubmitQuizAnswer submitQuizAnswerUseCase;
  final CompleteQuiz completeQuizUseCase;
  final AbandonQuiz abandonQuizUseCase;

  QuizProvider({
    required this.userId,
    required this.startQuizUseCase,
    required this.getQuizQuestionsUseCase,
    required this.submitQuizAnswerUseCase,
    required this.completeQuizUseCase,
    required this.abandonQuizUseCase,
  });

  List<Question> questions = <Question>[];
  final Map<String, UserAnswer> answeredQuestions = <String, UserAnswer>{};
  final Map<String, String> _correctOptions = <String, String>{};
  final Map<String, String> _explanations = <String, String>{};

  String? sessionId;
  QuizAttempt? currentQuizAttempt;

  Timer? _timer;
  int _remainingSeconds = 0;
  int _currentQuestionIndex = 0;
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;
  int get remainingSeconds => _remainingSeconds;
  int get currentQuestionIndex => _currentQuestionIndex;
  bool get hasNextQuestion => _currentQuestionIndex < questions.length - 1;
  bool get hasPreviousQuestion => _currentQuestionIndex > 0;

  Question? get currentQuestion {
    if (_currentQuestionIndex >= questions.length) {
      return null;
    }
    return questions[_currentQuestionIndex];
  }

  String? get currentAnswerOption {
    final question = currentQuestion;
    if (question == null) {
      return null;
    }
    return answeredQuestions[question.id]?.selectedOption;
  }

  bool? get isCurrentAnswerCorrect {
    final question = currentQuestion;
    if (question == null) {
      return null;
    }
    return answeredQuestions[question.id]?.isCorrect;
  }

  String? get currentCorrectOption {
    final question = currentQuestion;
    if (question == null) {
      return null;
    }
    return _correctOptions[question.id];
  }

  String? get currentExplanation {
    final question = currentQuestion;
    if (question == null) {
      return null;
    }
    return _explanations[question.id];
  }

  String get formattedTime {
    final minutes = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void setUserId(String? value) {
    final nextUserId = value ?? '';

    if (userId == nextUserId) {
      return;
    }

    _timer?.cancel();
    userId = nextUserId;
    sessionId = null;
    questions = <Question>[];
    answeredQuestions.clear();
    _correctOptions.clear();
    _explanations.clear();
    currentQuizAttempt = null;
    _currentQuestionIndex = 0;
    _remainingSeconds = 0;
    _errorMessage = null;
    _isLoading = false;
    _isSubmitting = false;
    notifyListeners();
  }

  Future<void> startQuiz({
    required String subjectId,
    int questionCount = 20,
    bool isTimed = true,
    int timeLimitMinutes = 30,
    bool fromErrorNotebook = false,
  }) async {
    if (userId.isEmpty) {
      _errorMessage = 'Quiz başlatmak için giriş yapmalısınız.';
      notifyListeners();
      return;
    }

    _setLoading(true);

    try {
      _errorMessage = null;

      final session = await startQuizUseCase(
        subjectId: subjectId,
        questionCount: questionCount,
        isTimed: isTimed,
        timeLimitSeconds: timeLimitMinutes * 60,
        fromErrorNotebook: fromErrorNotebook,
      );

      final loadedQuestions = await getQuizQuestionsUseCase(
        session.sessionId,
      );

      if (loadedQuestions.isEmpty) {
        throw StateError('Bu sınav için soru bulunamadı.');
      }

      sessionId = session.sessionId;
      questions = loadedQuestions;
      answeredQuestions.clear();
      _correctOptions.clear();
      _explanations.clear();
      _currentQuestionIndex = 0;
      _remainingSeconds = session.isTimed
          ? (session.timeLimitSeconds ?? timeLimitMinutes * 60)
          : 0;

      currentQuizAttempt = QuizAttempt(
        id: session.sessionId,
        userId: userId,
        subjectId: subjectId,
        status: QuizStatus.running,
        totalQuestions: questions.length,
        correctAnswers: 0,
        wrongAnswers: 0,
        blankAnswers: questions.length,
        durationSeconds: 0,
        isTimed: session.isTimed,
        timeLimitSeconds: session.timeLimitSeconds,
        startedAt: session.startedAt ?? DateTime.now(),
      );

      _startTimerIfNeeded();
      notifyListeners();
    } catch (error) {
      _errorMessage = _friendlyError(error);
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> selectAnswer(String option) async {
    final question = currentQuestion;
    final id = sessionId;

    if (question == null ||
        id == null ||
        _isSubmitting ||
        answeredQuestions.containsKey(question.id)) {
      return;
    }

    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    final normalizedOption = option.toUpperCase();

    try {
      final result = await submitQuizAnswerUseCase(
        sessionId: id,
        questionId: question.id,
        selectedOption: normalizedOption,
      );

      _correctOptions[question.id] = result.correctOption;
      _explanations[question.id] = result.explanation;

      answeredQuestions[question.id] = UserAnswer(
        id: result.answerId,
        userId: userId,
        questionId: question.id,
        quizAttemptId: id,
        selectedOption: normalizedOption,
        isCorrect: result.isCorrect,
        answeredAt: DateTime.now(),
      );

      notifyListeners();
    } catch (error) {
      _errorMessage = _friendlyError(error);
      notifyListeners();
      rethrow;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> completeQuiz({bool timeExpired = false}) async {
    final id = sessionId;

    if (id == null || _isSubmitting) {
      return;
    }

    _isSubmitting = true;
    _timer?.cancel();
    notifyListeners();

    try {
      final result = await completeQuizUseCase(id);

      currentQuizAttempt = currentQuizAttempt?.copyWith(
        status: QuizStatus.completed,
        correctAnswers: result.correctAnswers,
        wrongAnswers: result.wrongAnswers,
        blankAnswers: result.blankAnswers,
        durationSeconds: result.durationSeconds,
        score: result.net,
        completedAt: DateTime.now(),
      );

      if (timeExpired) {
        _errorMessage = null;
      }

      notifyListeners();
    } catch (error) {
      _errorMessage = _friendlyError(error);
      notifyListeners();
      rethrow;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> abandonQuiz() async {
    final id = sessionId;

    if (id == null) {
      return;
    }

    _timer?.cancel();

    try {
      await abandonQuizUseCase(id);
    } finally {
      sessionId = null;
      questions = <Question>[];
      answeredQuestions.clear();
      _correctOptions.clear();
      _explanations.clear();
      currentQuizAttempt = null;
      _currentQuestionIndex = 0;
      _remainingSeconds = 0;
      notifyListeners();
    }
  }

  void nextQuestion() {
    if (!hasNextQuestion) {
      return;
    }

    _currentQuestionIndex++;
    notifyListeners();
  }

  void previousQuestion() {
    if (!hasPreviousQuestion) {
      return;
    }

    _currentQuestionIndex--;
    notifyListeners();
  }

  void goToQuestion(int index) {
    if (index < 0 || index >= questions.length) {
      return;
    }

    _currentQuestionIndex = index;
    notifyListeners();
  }

  void _startTimerIfNeeded() {
    _timer?.cancel();

    if (currentQuizAttempt?.isTimed != true) {
      return;
    }

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
          notifyListeners();
          return;
        }

        _timer?.cancel();
        unawaited(completeQuiz(timeExpired: true));
      },
    );
  }

  String _friendlyError(Object error) {
    final message = error.toString();

    if (message.contains('QUESTION_ALREADY_ANSWERED')) {
      return 'Bu soru zaten cevaplandı.';
    }

    if (message.contains('QUIZ_TIME_EXPIRED')) {
      return 'Sınav süresi doldu.';
    }

    if (message.contains('SESSION_NOT_FOUND')) {
      return 'Quiz oturumu bulunamadı.';
    }

    if (message.contains('NO_QUESTIONS')) {
      return 'Bu konuda yeterli soru bulunamadı.';
    }

    return 'Quiz işlemi gerçekleştirilemedi.';
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
