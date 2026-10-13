import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/interaction_model.dart';
import 'notification_service.dart';

class InteractionService {
  static const allowedTypes = {'hug', 'kiss', 'nudge', 'miss_you', 'infinity'};

  final SupabaseClient client;
  InteractionService(this.client);

  Stream<List<Interaction>> getInteractionsStream(String userId, {String? partnerId}) {
    RealtimeChannel? channel;
    late final StreamController<List<Interaction>> controller;
    var active = true;

    Future<void> emitInteractions() async {
      if (!active || controller.isClosed) return;

      try {
        final query = client.from('interactions').select();
        final data = partnerId == null || partnerId.isEmpty
            ? await query.eq('receiver_id', userId).order('created_at', ascending: false)
            : await query
                .or('and(sender_id.eq.$userId,receiver_id.eq.$partnerId),and(sender_id.eq.$partnerId,receiver_id.eq.$userId)')
                .order('created_at', ascending: false);

        if (!active || controller.isClosed) return;

        final interactions = data
            .map((row) => Interaction.fromMap(Map<String, dynamic>.from(row as Map)))
            .toList();

        controller.add(interactions);
      } catch (error, stackTrace) {
        if (!active || controller.isClosed) return;
        controller.addError(error, stackTrace);
      }
    }

    Future<void> start() async {
      final session = client.auth.currentSession;
      if (session == null || session.accessToken.isEmpty) {
        if (!controller.isClosed) {
          controller.addError(const AuthException('Realtime requires an active session'));
        }
        return;
      }

      final realtimeChannel = client.channel('bestie-interactions-$userId-${partnerId ?? 'all'}');
      channel = realtimeChannel;

      realtimeChannel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'interactions',
            callback: (_) {
              unawaited(emitInteractions());
            },
          )
          .subscribe((status, error) {
            if (!active || controller.isClosed) return;

            if (status == RealtimeSubscribeStatus.subscribed) {
              debugPrint('🟢 BESTIE INTERACTION Realtime SUBSCRIBED');
              unawaited(emitInteractions());
              return;
            }

            if (status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut) {
              debugPrint('🔴 BESTIE INTERACTION Realtime status=$status error=$error');
              controller.addError(
                RealtimeSubscribeException(status, error),
              );
            }
          });
    }

    controller = StreamController<List<Interaction>>(
      sync: false,
      onListen: () {
        unawaited(start());
      },
      onCancel: () async {
        active = false;
        if (channel != null) {
          await client.removeChannel(channel!);
        }
      },
    );

    return controller.stream;
  }

  Future<void> sendInteraction(
    String senderId,
    String receiverId,
    String type,
  ) async {
    final normalizedType = type.trim().toLowerCase();
    if (!allowedTypes.contains(normalizedType)) {
      throw const FormatException('Invalid interaction type');
    }

    final currentUser = client.auth.currentUser;
    if (currentUser == null || currentUser.id != senderId) {
      throw const AuthException(
        'You must be signed in to send an interaction',
      );
    }

    if (senderId == receiverId) {
      throw const FormatException(
        'You cannot send an interaction to yourself',
      );
    }

    await client.from('interactions').insert({
      'id': const Uuid().v4(),
      'sender_id': senderId,
      'receiver_id': receiverId,
      'type': normalizedType,
      'created_at': DateTime.now().toIso8601String(),
    });
    try {
      const labels = {'hug':'Hug 🫂','kiss':'Kiss 💋','nudge':'Nudge 👉','miss_you':'Miss you 🥺','infinity':'Forever ∞'};
      await NotificationService(client).create(userId: receiverId, title: labels[normalizedType] ?? 'Etkileşim', body: 'Partnerinden yeni bir etkileşim geldi.', type: 'interaction', data: {'action': 'interaction', 'interaction_type': normalizedType});
    } catch (e) { debugPrint('Interaction notification skipped: $e'); }
  }
}
