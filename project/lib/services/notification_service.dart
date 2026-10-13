import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppNotification {
  final String id, userId, title, body, type;
  final bool isRead;
  final Map<String, dynamic> data;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.data,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> m) =>
      AppNotification(
        id: m['id'].toString(),
        userId: m['user_id'].toString(),
        title: (m['title'] ?? '').toString(),
        body: (m['body'] ?? '').toString(),
        type: (m['type'] ?? 'general').toString(),
        data: m['data'] is Map
            ? Map<String, dynamic>.from(m['data'] as Map)
            : <String, dynamic>{},
        isRead: m['is_read'] == true || m['read_at'] != null,
        createdAt: DateTime.tryParse(
          m['created_at']?.toString() ?? '',
        ) ??
            DateTime.now(),
      );
}

class NotificationService {
  final SupabaseClient client;

  NotificationService(this.client);

  Future<bool> create({
    required String userId,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic> data = const {},
  }) async {
    try {
      final id = await client.rpc(
        'create_notification',
        params: {
          'p_user_id': userId,
          'p_title': title,
          'p_body': body,
          'p_type': type,
          'p_data': data,
        },
      );

      debugPrint('[FCM] notification created: $id');

      final response = await client.functions.invoke(
        'send-push-notification',
        body: {
          'notification_id': id.toString(),
        },
      );

      debugPrint('[FCM] push response: ${response.data}');
      final raw = response.data;
      if (raw is Map) {
        final sent = int.tryParse(raw['sent']?.toString() ?? '');
        if (sent != null && sent <= 0) {
          debugPrint('[FCM] push was not delivered to any registered device token');
          return false;
        }
      }
      return true;
    } catch (e, st) {
      // Bildirim DB'ye kaydedilmiş olabilir; push başarısız olsa bile
      // uygulamanın geri kalanını bozma.
      debugPrint('[FCM] notification error: $e');
      debugPrint('$st');
      return false;
    }
  }

  Stream<List<AppNotification>> stream(String userId) {
    return client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map(
          (rows) => rows
          .where((r) => r['user_id'] == userId)
          .map(
            (r) => AppNotification.fromMap(
          Map<String, dynamic>.from(r),
        ),
      )
          .toList(),
    );
  }

  Future<void> markRead(String id) async {
    await client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', id);
  }

  Future<void> markAllRead(String userId) async {
    await client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }
}