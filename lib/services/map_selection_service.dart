import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/map_selection_model.dart';
import 'notification_service.dart';

class MapSelectionService {
  final SupabaseClient client;

  MapSelectionService(this.client);

  Future<List<MapSelection>> _fetch(String userId, String partnerId) async {
    final rows = await client
        .from('map_selections')
        .select()
        .or('and(user_id.eq.$userId,partner_id.eq.$partnerId),and(user_id.eq.$partnerId,partner_id.eq.$userId)')
        .order('created_at', ascending: true);

    return (rows as List)
        .map((row) => MapSelection.fromMap(Map<String, dynamic>.from(row as Map)))
        .where((selection) =>
            (selection.userId == userId && selection.partnerId == partnerId) ||
            (selection.userId == partnerId && selection.partnerId == userId))
        .toList();
  }

  Stream<List<MapSelection>> watchSelections(String userId, String partnerId) {
    late final StreamController<List<MapSelection>> controller;
    RealtimeChannel? channel;
    var active = true;

    Future<void> refresh() async {
      if (!active || controller.isClosed) return;
      try {
        final selections = await _fetch(userId, partnerId);
        if (active && !controller.isClosed) controller.add(selections);
      } catch (e, st) {
        if (active && !controller.isClosed) controller.addError(e, st);
      }
    }

    controller = StreamController<List<MapSelection>>(
      onListen: () async {
        await refresh();
        if (!active || controller.isClosed) return;

        final realtimeChannel = client.channel(
          'bestie-map-selections-$userId-$partnerId-${const Uuid().v4()}',
        );
        channel = realtimeChannel;
        realtimeChannel
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'map_selections',
              callback: (_) => unawaited(refresh()),
            )
            .subscribe();
      },
      onCancel: () async {
        active = false;
        final activeChannel = channel;
        channel = null;
        if (activeChannel != null) await client.removeChannel(activeChannel);
      },
    );

    return controller.stream;
  }

  Future<void> saveCountry({
    required String userId,
    required String partnerId,
    required String countryCode,
    required String countryName,
  }) async {
    await _validate(userId, partnerId);
    await client.from('map_selections').upsert({
      'id': const Uuid().v4(),
      'user_id': userId,
      'partner_id': partnerId,
      'selection_key': '${userId}|${partnerId}|${countryCode.toUpperCase()}|COUNTRY',
      'country_code': countryCode.toUpperCase(),
      'country_name': countryName,
      'city_name': null,
      'state_name': null,
      'city_id': null,
      'latitude': null,
      'longitude': null,
    }, onConflict: 'selection_key');
    try {
      await NotificationService(client).create(
        userId: partnerId, title: 'Yeni ülke seçildi 📍', body: countryName, type: 'map',
        data: {'action': 'country_added', 'country_code': countryCode.toUpperCase()},
      );
    } catch (e) {}
  }

  Future<void> saveCity({
    required String userId,
    required String partnerId,
    required String countryCode,
    required String countryName,
    required String cityName,
    String? stateName,
    int? cityId,
    double? latitude,
    double? longitude,
  }) async {
    await _validate(userId, partnerId);
    await client.from('map_selections').upsert({
      'id': const Uuid().v4(),
      'user_id': userId,
      'partner_id': partnerId,
      'selection_key': '${userId}|${partnerId}|${countryCode.toUpperCase()}|CITY|${cityName.trim().toLowerCase()}',
      'country_code': countryCode.toUpperCase(),
      'country_name': countryName,
      'city_name': cityName.trim(),
      'state_name': stateName,
      'city_id': cityId,
      'latitude': latitude,
      'longitude': longitude,
    }, onConflict: 'selection_key');
    try {
      await NotificationService(client).create(
        userId: partnerId, title: 'Yeni şehir seçildi 📍', body: cityName.trim(), type: 'map',
        data: {'action': 'city_added', 'country_code': countryCode.toUpperCase(), 'city_name': cityName.trim()},
      );
    } catch (e) {}
  }

  Future<void> deleteSelection(String id) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null) {
      throw const AuthException('You must be signed in to delete a map selection');
    }

    final deleted = await client
        .from('map_selections')
        .delete()
        .eq('id', id)
        .eq('user_id', currentUser.id)
        .select('id');

    if (deleted.isEmpty) {
      throw const PostgrestException(
        message: 'Selection was not deleted. Check the map_selections DELETE policy.',
      );
    }
  }

  Future<void> _validate(String userId, String partnerId) async {
    final current = client.auth.currentUser;
    if (current == null || current.id != userId) {
      throw const AuthException('You must be signed in to save a map selection');
    }
    if (userId == partnerId) {
      throw const FormatException('You cannot create a shared selection with yourself');
    }
  }
}
