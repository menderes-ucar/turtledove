import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_service.dart';

class PairingService {
  final SupabaseClient client;
  PairingService(this.client);

  Future<String?> unpairCurrentUser() async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null) {
      throw const AuthException('You must be signed in to end the pairing');
    }

    try {
      final result = await client.rpc('unpair_current_user');
      if (result is Map) {
        final notificationId = result['notification_id']?.toString();
        if (notificationId != null && notificationId.isNotEmpty) {
          // The DB transaction has already ended the pairing and preserved the
          // relationship history. Push delivery is intentionally a separate
          // step so an FCM outage can never roll back the relationship change.
          await NotificationService(client).deliverExisting(notificationId);
        }
        return result['partner_id']?.toString();
      }
      return result?.toString();
    } on PostgrestException catch (e) {
      print('🔴 PairingService.unpairCurrentUser error: ${e.message}');
      rethrow;
    } catch (e) {
      print('🔴 PairingService.unpairCurrentUser error: $e');
      rethrow;
    }
  }

  Future<String?> getRelationshipId(String partnerId) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null) {
      throw const AuthException('You must be signed in to read relationship history');
    }
    final result = await client.rpc(
      'get_relationship_pair_id',
      params: {'p_partner_id': partnerId},
    );
    return result?.toString();
  }

  Future<bool> pairWithCode(String currentUserId, String pairCode) async {
    final normalizedCode = pairCode.trim();
    if (normalizedCode.length != 6) {
      throw const FormatException('Pair code must be 6 digits');
    }

    final currentUser = client.auth.currentUser;
    if (currentUser == null || currentUser.id != currentUserId) {
      throw const AuthException('You must be signed in to pair');
    }

    try {
      await client.rpc(
        'pair_users_by_code',
        params: {'p_pair_code': normalizedCode},
      );
      try {
        final me = await client.from('profiles').select('paired_with,username').eq('id', currentUserId).maybeSingle();
        final partnerId = me?['paired_with']?.toString();
        final username = (me?['username'] ?? 'Partnerin').toString();
        if (partnerId != null && partnerId.isNotEmpty) {
          await NotificationService(client).create(
            userId: partnerId,
            title: 'Eşleşme tamamlandı 💕',
            body: '$username seninle eşleşti.',
            type: 'pairing',
            data: {
              'action': 'paired',
              'partner_name': username,
              'event_key': 'pairing:$currentUserId:$partnerId',
            },
          );
        }
      } catch (e) {
        print('🟡 Pairing notification skipped: $e');
      }
      return true;
    } on PostgrestException catch (e) {
      print('🔴 PairingService.pairWithCode error: ${e.message}');
      rethrow;
    } catch (e) {
      print('🔴 PairingService.pairWithCode error: $e');
      rethrow;
    }
  }
}
