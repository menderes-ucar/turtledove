import '../../domain/entities/analytics_summary.dart';
import '../../domain/repositories/analytics_repository.dart';
import '../datasources/analytics_remote_datasource.dart';
class AnalyticsRepositoryImpl implements AnalyticsRepository {
  final AnalyticsRemoteDataSource remote;
  const AnalyticsRepositoryImpl(this.remote);
  @override Future<AnalyticsSummary> summary()=>remote.summary();
}
