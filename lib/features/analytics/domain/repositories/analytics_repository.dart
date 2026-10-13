import '../entities/analytics_summary.dart';
abstract class AnalyticsRepository {
  Future<AnalyticsSummary> summary();
}
