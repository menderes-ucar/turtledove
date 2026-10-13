import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/analytics_summary_model.dart';

class AnalyticsRemoteDataSource {
  final SupabaseClient client;

  const AnalyticsRemoteDataSource(this.client);

  Future<AnalyticsSummaryModel> summary() async {
    final response = await client
        .from('user_quiz_attempts')
        .select(
          'total_questions,correct_answers,wrong_answers,blank_answers',
        )
        .eq('status', 'completed');

    final rows = response as List;

    var totalQuestions = 0;
    var correct = 0;
    var wrong = 0;
    var blank = 0;

    for (final row in rows) {
      final json = Map<String, dynamic>.from(row);

      totalQuestions +=
          (json['total_questions'] as num?)?.toInt() ?? 0;
      correct += (json['correct_answers'] as num?)?.toInt() ?? 0;
      wrong += (json['wrong_answers'] as num?)?.toInt() ?? 0;
      blank += (json['blank_answers'] as num?)?.toInt() ?? 0;
    }

    final success = totalQuestions == 0
        ? 0.0
        : (correct / totalQuestions) * 100;
    final net = correct - (wrong / 4);

    return AnalyticsSummaryModel(
      totalQuestions: totalQuestions,
      correct: correct,
      wrong: wrong,
      blank: blank,
      tests: rows.length,
      success: success,
      net: net,
    );
  }
}
