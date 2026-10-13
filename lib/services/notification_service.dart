import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_localizer.dart';

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
      // The recipient's language is authoritative. The sender's language must
      // never leak into the recipient's push notification.
      String recipientLanguage = 'en';
      try {
        final profile = await client
            .from('profiles')
            .select('language_code')
            .eq('id', userId)
            .maybeSingle();
        recipientLanguage = NotificationLocalizer.normalize(
          profile?['language_code']?.toString(),
        );
      } catch (e) {
        debugPrint('[FCM] recipient language lookup failed: $e');
      }

      final localized = NotificationLocalizer.localize(
        language: recipientLanguage,
        type: type,
        title: title,
        body: body,
        data: data,
      );

      final senderId = client.auth.currentUser?.id;
      if (senderId == null) {
        debugPrint('[FCM] notification skipped: no authenticated sender');
        return false;
      }

      final id = await client.rpc(
        'create_notification',
        params: {
          'p_user_id': userId,
          'p_title': localized['title'],
          'p_body': localized['body'],
          'p_type': type,
          'p_data': {
            ...data,
            // The Edge Function uses this immutable server-side identity to
            // authorize client-requested push delivery.
            'sender_id': senderId,
            'language_code': recipientLanguage,
          },
        },
      );

      debugPrint('[FCM] notification created: $id ($recipientLanguage)');

      return deliverExisting(id.toString());
    } catch (e, st) {
      // Bildirim DB'ye kaydedilmiş olabilir; push başarısız olsa bile
      // uygulamanın geri kalanını bozma.
      debugPrint('[FCM] notification error: $e');
      debugPrint('$st');
      return false;
    }
  }

  /// Delivers a notification row that already exists in the database.
  /// Kept separate so server-side RPCs (for example unpair) can create the
  /// notification atomically and the client can then request FCM delivery.
  Future<bool> deliverExisting(String notificationId) async {
    try {
      final response = await client.functions.invoke(
        'send-push-notification',
        body: {'notification_id': notificationId},
      );
      debugPrint('[FCM] push response: ${response.data}');
      final raw = response.data;
      if (raw is Map) {
        final sent = int.tryParse(raw['sent']?.toString() ?? '');
        if (sent != null && sent <= 0) return false;
      }
      return true;
    } catch (e, st) {
      debugPrint('[FCM] push delivery failed: $e\n$st');
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