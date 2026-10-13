import 'package:flutter/foundation.dart';
import '../../domain/entities/analytics_summary.dart';
import '../../domain/repositories/analytics_repository.dart';
class AnalyticsProvider extends ChangeNotifier {
  final AnalyticsRepository repository;
  AnalyticsProvider(this.repository);
  AnalyticsSummary? summary;
  bool loading=false;
  String? error;
  Future<void> load()async {
    loading=true;
    notifyListeners();
    try {
      summary=await repository.summary();
      error=null;
    }
    catch(e) {
      error='İstatistikler yüklenemedi.';
    }
    finally {
      loading=false;
      notifyListeners();
    }
  }
}
