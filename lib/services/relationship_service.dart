import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RelationshipDailyStats {
  final DateTime day;
  final int messages;
  final int photos;
  final int videos;
  final int games;
  final int interactions;
  final int completedTodos;

  const RelationshipDailyStats({
    required this.day,
    required this.messages,
    required this.photos,
    required this.videos,
    required this.games,
    required this.interactions,
    required this.completedTodos,
  });

  int get totalActivities => messages + photos + videos + games + interactions + completedTodos;
  bool get hasActivity => totalActivities > 0;

  factory RelationshipDailyStats.fromMap(Map<String, dynamic> map, DateTime day) {
    int n(String key) => (map[key] as num?)?.toInt() ?? 0;
    return RelationshipDailyStats(
      day: day,
      messages: n('messages'),
      photos: n('photos'),
      videos: n('videos'),
      games: n('games'),
      interactions: n('interactions'),
      completedTodos: n('completed_todos'),
    );
  }
}

class RelationshipStreak {
  final int current;
  final int longest;
  final bool activeToday;
  final DateTime? lastActiveDay;

  const RelationshipStreak({
    required this.current,
    required this.longest,
    required this.activeToday,
    required this.lastActiveDay,
  });

  factory RelationshipStreak.fromMap(Map<String, dynamic> map) => RelationshipStreak(
        current: (map['current_streak'] as num?)?.toInt() ?? 0,
        longest: (map['longest_streak'] as num?)?.toInt() ?? 0,
        activeToday: map['active_today'] == true,
        lastActiveDay: map['last_active_day'] == null ? null : DateTime.tryParse(map['last_active_day'].toString()),
      );
}

class RelationshipService {
  final SupabaseClient client;
  RelationshipService(this.client);

  Future<RelationshipDailyStats> getToday(String userId, String partnerId) async {
    final raw = await client.rpc('get_relationship_daily_stats', params: {
      'p_user_id': userId,
      'p_partner_id': partnerId,
      'p_day': DateTime.now().toUtc().toIso8601String().substring(0, 10),
    });
    final row = raw is List ? (raw.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(raw.first as Map)) : Map<String, dynamic>.from(raw as Map);
    return RelationshipDailyStats.fromMap(row, DateTime.now());
  }

  Future<RelationshipStreak> getStreak(String userId, String partnerId) async {
    final raw = await client.rpc('get_relationship_streak', params: {
      'p_user_id': userId,
      'p_partner_id': partnerId,
    });
    final row = raw is List ? (raw.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(raw.first as Map)) : Map<String, dynamic>.from(raw as Map);
    return RelationshipStreak.fromMap(row);
  }

  Future<List<RelationshipDailyStats>> getRecentDays(String userId, String partnerId, {int days = 7}) async {
    final safeDays = days.clamp(1, 30);
    final raw = await client.rpc('get_relationship_recent_stats', params: {
      'p_user_id': userId,
      'p_partner_id': partnerId,
      'p_days': safeDays,
    });
    final rows = raw is List ? raw : const [];
    return rows.map((r) {
      final map = Map<String, dynamic>.from(r as Map);
      final day = DateTime.tryParse(map['day']?.toString() ?? '') ?? DateTime.now();
      return RelationshipDailyStats.fromMap(map, day);
    }).toList();
  }

  Future<void> ensureTodaySummaryNotification(String userId, String partnerId, {required String title, required String body}) async {
    try {
      await client.rpc('ensure_relationship_daily_notification', params: {
        'p_user_id': userId,
        'p_partner_id': partnerId,
        'p_title': title,
        'p_body': body,
      });
    } catch (e) {
      debugPrint('Relationship daily notification skipped: $e');
    }
  }
}
