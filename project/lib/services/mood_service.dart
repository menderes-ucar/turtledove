import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/mood_model.dart';
import 'notification_service.dart';

class MoodService {
  final SupabaseClient client;
  MoodService(this.client);

  Stream<List<MoodEntry>> getMoodsStream(String userId) {
    return client.from('mood_entries').stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((data) => (data as List)
        .where((m) => (m as Map<String, dynamic>)['user_id'] == userId)
        .map((m) => MoodEntry.fromMap(m as Map<String, dynamic>))
        .toList());
  }

  Future<void> addMood(String userId, int mood, {String? note, String? category}) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) {
      throw const AuthException('You must be signed in to save mood');
    }

    if (mood < 1 || mood > 5) {
      throw const FormatException('Mood must be between 1 and 5');
    }

    await client.from('mood_entries').insert({
      'id': const Uuid().v4(),
      'user_id': userId,
      'mood': mood,
      'note': note?.trim().isEmpty == true ? null : note?.trim(),
      'category': category,
      'created_at': DateTime.now().toIso8601String(),
    });
    try {
      final profile = await client.from('profiles').select('paired_with').eq('id', userId).maybeSingle();
      final partnerId = profile?['paired_with']?.toString();
      if (partnerId != null && partnerId.isNotEmpty) {
        await NotificationService(client).create(userId: partnerId, title: 'Partnerinin ruh hali güncellendi', body: 'Partnerin yeni bir ruh hali paylaştı.', type: 'mood', data: {'action': 'mood_updated', 'mood': mood});
      }
    } catch (e) {}
  }

  Future<Map<String, dynamic>> getMoodStats(String userId) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) {
      throw const AuthException('You must be signed in to load mood stats');
    }

    final data = await client
      .from('mood_entries')
      .select()
      .eq('user_id', userId)
      .order('created_at', ascending: false)
      .limit(30);

    if (data.isEmpty) return {};

    final moods = (data as List).map((m) => m['mood'] as int).toList();
    final average = moods.isEmpty ? 0 : moods.reduce((a, b) => a + b) / moods.length;
    final highest = moods.isEmpty ? 0 : moods.reduce((a, b) => a > b ? a : b);
    final lowest = moods.isEmpty ? 0 : moods.reduce((a, b) => a < b ? a : b);

    return {
      'average': average,
      'highest': highest,
      'lowest': lowest,
      'count': moods.length,
    };
  }
}
