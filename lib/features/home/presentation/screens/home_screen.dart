import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/router/route_names.dart';
import '../../../analytics/presentation/providers/analytics_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final analytics = context.watch<AnalyticsProvider>();

    final fullName = auth.user?.fullName?.trim();
    final greeting = fullName == null || fullName.isEmpty
        ? 'Merhaba 👋'
        : 'Merhaba $fullName 👋';

    return Scaffold(
      appBar: AppBar(
        title: const Text('KPSS Kolay'),
        actions: [
          IconButton(
            onPressed: auth.loading ? null : auth.signOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Çıkış yap',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: analytics.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              greeting,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Bugün ne çalışmak istersin?'),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _HomeCard(
                    title: 'Dersler',
                    icon: Icons.menu_book,
                    onTap: () => context.push(RouteNames.subjects),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _HomeCard(
                    title: 'Yanlış Defteri',
                    icon: Icons.error_outline,
                    onTap: () => context.push(RouteNames.errors),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _HomeCard(
                    title: 'Notlar',
                    icon: Icons.note_alt,
                    onTap: () => context.push(RouteNames.notes),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _HomeCard(
                    title: 'İstatistik',
                    icon: Icons.insights,
                    onTap: () => context.push(RouteNames.analytics),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (analytics.summary != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      _HomeStat(
                        label: 'Soru',
                        value: analytics.summary!.totalQuestions.toString(),
                      ),
                      _HomeStat(
                        label: 'Doğru',
                        value: analytics.summary!.correct.toString(),
                      ),
                      _HomeStat(
                        label: 'Yanlış',
                        value: analytics.summary!.wrong.toString(),
                      ),
                      _HomeStat(
                        label: 'Net',
                        value: analytics.summary!.net.toStringAsFixed(2),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _HomeCard({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Icon(icon, size: 30),
              const SizedBox(height: 8),
              Text(title),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeStat extends StatelessWidget {
  final String label;
  final String value;

  const _HomeStat({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ],
    );
  }
}
