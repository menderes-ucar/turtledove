import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/countdown_model.dart';
import 'notification_service.dart';

class CountdownService {
  final SupabaseClient client;
  CountdownService(this.client);

  Stream<List<Countdown>> getCountdownsStream(String userId) {
    return client.from('countdowns').stream(primaryKey: ['id'])
      .order('target_date', ascending: true)
      .map((data) => (data as List)
        .where((c) => (c as Map<String, dynamic>)['user_id'] == userId)
        .map((c) => Countdown.fromMap(c as Map<String, dynamic>))
        .toList());
  }

  Future<void> addCountdown(String userId, String title, DateTime targetDate, String type, {String? emoji}) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) {
      throw const AuthException('You must be signed in to add a countdown');
    }

    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw const FormatException('Countdown title cannot be empty');
    }

    if (targetDate.isBefore(DateTime.now())) {
      throw const FormatException('Countdown date cannot be in the past');
    }

    await client.from('countdowns').insert({
      'id': const Uuid().v4(),
      'user_id': userId,
      'title': normalizedTitle,
      'target_date': targetDate.toIso8601String(),
      'type': type,
      'emoji': emoji,
      'created_at': DateTime.now().toIso8601String(),
    });
    try {
      final profile = await client.from('profiles').select('paired_with').eq('id', userId).maybeSingle();
      final partnerId = profile?['paired_with']?.toString();
      if (partnerId != null && partnerId.isNotEmpty) {
        await NotificationService(client).create(userId: partnerId, title: 'Yeni geri sayım', body: normalizedTitle, type: 'countdown');
      }
    } catch (e) {}
  }

  Future<void> deleteCountdown(String countdownId) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null) {
      throw const AuthException('You must be signed in to delete a countdown');
    }

    await client
        .from('countdowns')
        .delete()
        .eq('id', countdownId)
        .eq('user_id', currentUser.id);
  }
}
