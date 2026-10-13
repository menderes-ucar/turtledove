import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/question_model.dart';
import '../models/quiz_session_model.dart';
class QuizRemoteDataSource {
  final SupabaseClient client;
  const QuizRemoteDataSource(this.client);
  Future<QuizSessionModel> startSession( {
    required String subjectId,
    required int questionCount,
    required bool isTimed,
    required int timeLimitSeconds,
    required bool fromErrorNotebook,
  }) async {
    final result = await client.rpc(
    fromErrorNotebook ? 'start_error_quiz_session' : 'start_quiz_session',
    params: {
      'p_subject_id': subjectId,
      'p_question_count': questionCount,
      'p_is_timed': isTimed,
      'p_time_limit_seconds': timeLimitSeconds,
    },
    );
    return QuizSessionModel.fromJson(Map<String, dynamic>.from(result as Map));
  }
  Future<List<QuestionModel>> getQuestions(String sessionId) async {
    final result = await client.rpc('get_quiz_questions', params: {
      'p_session_id': sessionId
    });
    return (result as List)
    .map((row) => QuestionModel.fromJson(Map<String, dynamic>.from(row as Map)))
    .toList(growable: false);
  }
  Future<Map<String, dynamic>> submitAnswer( {
    required String sessionId,
    required String questionId,
    required String selectedOption,
  }) async {
    final result = await client.rpc('submit_quiz_answer', params: {
      'p_session_id': sessionId,
      'p_question_id': questionId,
      'p_selected_option': selectedOption.toUpperCase(),
    });
    return Map<String, dynamic>.from(result as Map);
  }
  Future<Map<String, dynamic>> completeSession(String sessionId) async {
    final result = await client.rpc('complete_quiz_session', params: {
      'p_session_id': sessionId
    });
    return Map<String, dynamic>.from(result as Map);
  }
  Future<void> abandonSession(String sessionId) async {
    await client.rpc('abandon_quiz_session', params: {
      'p_session_id': sessionId
    });
  }
}
