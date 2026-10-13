import '../../domain/entities/analytics_summary.dart';

class AnalyticsSummaryModel extends AnalyticsSummary {
  const AnalyticsSummaryModel({
    required super.totalQuestions,
    required super.correct,
    required super.wrong,
    required super.blank,
    required super.tests,
    required super.success,
    required super.net,
  });
}
