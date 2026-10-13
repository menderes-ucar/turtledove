import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/shared_place_model.dart';
import 'notification_service.dart';

class SharedPlaceService {
  final SupabaseClient client;

  SharedPlaceService(this.client);

  Future<List<SharedPlace>> _fetchPlaces(
      String userId,
      String partnerId,
      ) async {
    final rows = await client
        .from('places')
        .select()
        .or('user_id.eq.$userId,partner_id.eq.$userId')
        .order('created_at', ascending: false);

    return (rows as List)
        .map(
          (row) => SharedPlace.fromMap(
        Map<String, dynamic>.from(row as Map),
      ),
    )
        .where(
          (place) =>
      (place.userId == userId && place.partnerId == partnerId) ||
          (place.userId == partnerId && place.partnerId == userId),
    )
        .toList();
  }

  Stream<List<SharedPlace>> watchPlaces(
      String userId,
      String partnerId,
      ) {
    late final StreamController<List<SharedPlace>> controller;
    RealtimeChannel? channel;
    var active = true;

    Future<void> refresh() async {
      if (!active || controller.isClosed) return;

      try {
        final places = await _fetchPlaces(
          userId,
          partnerId,
        );

        if (!active || controller.isClosed) return;

        controller.add(places);
      } catch (e, st) {
        if (!active || controller.isClosed) return;

        controller.addError(e, st);
      }
    }

    controller = StreamController<List<SharedPlace>>(
      onListen: () async {
        await refresh();

        if (!active || controller.isClosed) return;

        final realtimeChannel = client.channel(
          'bestie-places-$userId-$partnerId-${const Uuid().v4()}',
        );

        channel = realtimeChannel;

        realtimeChannel
            .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'places',
          callback: (_) {
            unawaited(refresh());
          },
        )
            .subscribe((status, error) {
          if (!active || controller.isClosed) return;

          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            // Initial data remains usable even if Realtime is temporarily
            // unavailable.
          }
        });
      },
      onCancel: () async {
        active = false;

        final activeChannel = channel;
        channel = null;

        if (activeChannel != null) {
          await client.removeChannel(activeChannel);
        }
      },
    );

    return controller.stream;
  }

  Future<void> addPlace({
    required String userId,
    required String partnerId,
    required String title,
    String? note,
    required double latitude,
    required double longitude,
  }) async {
    final currentUser = client.auth.currentUser;

    if (currentUser == null || currentUser.id != userId) {
      throw const AuthException(
        'You must be signed in to add a place',
      );
    }

    if (userId == partnerId) {
      throw const FormatException(
        'You cannot create a shared place with yourself',
      );
    }

    final normalizedTitle = title.trim();

    if (normalizedTitle.isEmpty) {
      throw const FormatException(
        'Place title cannot be empty',
      );
    }

    await client.from('places').insert({
      'id': const Uuid().v4(),
      'user_id': userId,
      'partner_id': partnerId,
      'title': normalizedTitle,
      'note': note?.trim().isEmpty == true
          ? null
          : note?.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'created_at': DateTime.now().toIso8601String(),
    });

    // Notify partner about the newly saved place.
    try {
      await NotificationService(client).create(
        userId: partnerId,
        title: 'Yeni yer kaydedildi',
        body: normalizedTitle,
        type: 'place',
        data: {
          'title': normalizedTitle,
          'latitude': latitude,
          'longitude': longitude,
        },
      );
    } catch (e) {
      // Notification failure must not make the place creation fail.
    }
  }

  Future<void> deletePlace(String placeId) async {
    final currentUser = client.auth.currentUser;

    if (currentUser == null) {
      throw const AuthException(
        'You must be signed in to delete a place',
      );
    }

    await client
        .from('places')
        .delete()
        .eq('id', placeId);
  }
}