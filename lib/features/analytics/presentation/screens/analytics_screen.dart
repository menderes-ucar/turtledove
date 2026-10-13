import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/analytics_provider.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnalyticsProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AnalyticsProvider>();
    final summary = provider.summary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('İstatistikler'),
      ),
      body: provider.loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : summary == null
              ? Center(
                  child: Text(
                    provider.error ?? 'Henüz tamamlanmış test yok.',
                  ),
                )
              : GridView.count(
                  crossAxisCount: 2,
                  padding: const EdgeInsets.all(20),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  children: [
                    _StatCard(
                      title: 'Toplam Soru',
                      value: summary.totalQuestions.toString(),
                    ),
                    _StatCard(
                      title: 'Başarı',
                      value: '%${summary.success.toStringAsFixed(1)}',
                    ),
                    _StatCard(
                      title: 'Doğru',
                      value: summary.correct.toString(),
                    ),
                    _StatCard(
                      title: 'Yanlış',
                      value: summary.wrong.toString(),
                    ),
                    _StatCard(
                      title: 'Boş',
                      value: summary.blank.toString(),
                    ),
                    _StatCard(
                      title: 'Net',
                      value: summary.net.toStringAsFixed(2),
                    ),
                    _StatCard(
                      title: 'Test',
                      value: summary.tests.toString(),
                    ),
                  ],
                ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;

  const _StatCard({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
      ),
    );
  }
}
