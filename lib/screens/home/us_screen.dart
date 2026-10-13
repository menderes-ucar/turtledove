import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../localization/app_strings.dart';
import '../../providers/auth_provider.dart';
import '../../services/relationship_service.dart';

class UsScreen extends StatefulWidget {
  const UsScreen({super.key});
  @override
  State<UsScreen> createState() => _UsScreenState();
}

class _UsScreenState extends State<UsScreen> {
  Future<(RelationshipDailyStats, RelationshipStreak, List<RelationshipDailyStats>)>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final p = context.read<AuthProvider>().profile;
    if (p == null || p.pairedWith == null || p.pairedWith!.isEmpty) return;
    final service = context.read<RelationshipService>();
    _future = Future.wait<dynamic>([
      service.getToday(p.id, p.pairedWith!),
      service.getStreak(p.id, p.pairedWith!),
      service.getRecentDays(p.id, p.pairedWith!),
    ]).then((v) => (v[0] as RelationshipDailyStats, v[1] as RelationshipStreak, v[2] as List<RelationshipDailyStats>));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.read<AuthProvider>().profile;
    final s = AppStrings.of(context);
    if (p?.pairedWith == null || p!.pairedWith!.isEmpty) {
      return Center(child: Text(s.pairFirst, textAlign: TextAlign.center));
    }
    return FutureBuilder<(RelationshipDailyStats, RelationshipStreak, List<RelationshipDailyStats>)>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snap.hasError || !snap.hasData) {
          return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(s.relationshipLoadFailed, textAlign: TextAlign.center)));
        }
        final stats = snap.data!.$1;
        final streak = snap.data!.$2;
        final days = snap.data!.$3;
        return RefreshIndicator(
          onRefresh: () async { setState(_load); final future = _future; if (future != null) await future; },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _Hero(streak: streak),
              const SizedBox(height: 14),
              _SectionCard(
                icon: Icons.favorite_rounded,
                title: s.todayUs,
                subtitle: s.todayUsSubtitle,
                child: Column(children: [
                  _StatGrid(stats: stats),
                  const SizedBox(height: 14),
                  Align(alignment: Alignment.centerLeft, child: Text(s.activityTotal(stats.totalActivities), style: const TextStyle(fontWeight: FontWeight.w800))),
                ]),
              ),
              const SizedBox(height: 14),
              _SectionCard(
                icon: Icons.local_fire_department_rounded,
                title: s.relationshipStreak,
                subtitle: s.streakSubtitle,
                child: Column(children: [
                  Row(children: [
                    Expanded(child: _BigMetric(value: '${streak.current}', label: s.currentStreak)),
                    Expanded(child: _BigMetric(value: '${streak.longest}', label: s.longestStreak)),
                    Expanded(child: _BigMetric(value: streak.activeToday ? '✓' : '—', label: s.todayStatus)),
                  ]),
                  const SizedBox(height: 18),
                  _WeekStrip(days: days),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Hero extends StatelessWidget {
  final RelationshipStreak streak;
  const _Hero({required this.streak});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primary, scheme.primaryContainer]), borderRadius: BorderRadius.circular(28)),
      child: Row(children: [
        const Text('🔥', style: TextStyle(fontSize: 48)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.usTitle, style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(s.streakDays(streak.current), style: TextStyle(color: Colors.white.withOpacity(.92), fontSize: 16, fontWeight: FontWeight.w700)),
        ])),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon; final String title, subtitle; final Widget child;
  const _SectionCard({required this.icon, required this.title, required this.subtitle, required this.child});
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 10), Expanded(child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)))]),
      const SizedBox(height: 4), Text(subtitle), const SizedBox(height: 16), child,
    ])),
  );
}

class _StatGrid extends StatelessWidget {
  final RelationshipDailyStats stats;
  const _StatGrid({required this.stats});
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final data = [(Icons.chat_bubble_outline, '${stats.messages}', s.messages), (Icons.photo_camera_outlined, '${stats.photos}', s.photos), (Icons.videocam_outlined, '${stats.videos}', s.videos), (Icons.games_outlined, '${stats.games}', s.games), (Icons.favorite_border, '${stats.interactions}', s.interactions), (Icons.check_circle_outline, '${stats.completedTodos}', s.completedTasks)];
    return GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: data.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisExtent: 84, crossAxisSpacing: 8, mainAxisSpacing: 8), itemBuilder: (_, i) => Container(decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(data[i].$1, size: 21), const SizedBox(height: 5), Text(data[i].$2, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)), Text(data[i].$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))])));
  }
}

class _BigMetric extends StatelessWidget { final String value, label; const _BigMetric({required this.value, required this.label}); @override Widget build(BuildContext context) => Column(children: [Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))]); }

class _WeekStrip extends StatelessWidget { final List<RelationshipDailyStats> days; const _WeekStrip({required this.days}); @override Widget build(BuildContext context) { final s=AppStrings.of(context); return Row(children: List.generate(7, (i) { final d=days.length > i ? days[days.length-1-i] : null; return Expanded(child: Column(children: [Container(width: 34,height:34,alignment:Alignment.center,decoration:BoxDecoration(shape:BoxShape.circle,color:d?.hasActivity==true?Theme.of(context).colorScheme.primaryContainer:Theme.of(context).colorScheme.surfaceContainerHighest),child:Text(d?.hasActivity==true?'✓':'·',style:const TextStyle(fontWeight:FontWeight.w900))),const SizedBox(height:5),Text(d==null?'—':s.weekdayShort(d.day.weekday),style:const TextStyle(fontSize:10))])); })); } }
