import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/name_city_animal_model.dart';
import 'notification_service.dart';

class NameCityAnimalService {
  final SupabaseClient client;

  NameCityAnimalService(this.client);

  static const supportedLanguages = {'tr', 'en', 'de', 'es', 'fr'};

  String _requireUserId() {
    final id = client.auth.currentUser?.id;
    if (id == null || id.isEmpty) {
      throw const AuthException('Authentication required');
    }
    return id;
  }

  Future<NameCityAnimalState> createOrJoin({
    required String partnerId,
    required String languageCode,
  }) async {
    _requireUserId();
    final language = languageCode.trim().toLowerCase();
    if (!supportedLanguages.contains(language)) {
      throw const FormatException('Unsupported Name-City-Animal language');
    }

    final row = await client.rpc(
      'bestie_create_nca_v4',
      params: {
        'p_partner_id': partnerId,
        'p_language_code': language,
      },
    );
    return _state(row);
  }

  Future<NameCityAnimalState> getState(String sessionId) async {
    _requireUserId();
    final row = await client.rpc(
      'bestie_nca_state_v4',
      params: {'p_session_id': sessionId},
    );
    return _state(row);
  }

  Future<NameCityAnimalState> setReady(String sessionId, bool ready) async {
    _requireUserId();
    final row = await client.rpc(
      'bestie_nca_ready_v4',
      params: {
        'p_session_id': sessionId,
        'p_ready': ready,
      },
    );
    return _state(row);
  }

  Future<NameCityAnimalState> submit({
    required String sessionId,
    required String name,
    required String city,
    required String animal,
    required String plant,
    required String thing,
    required String country,
  }) async {
    _requireUserId();
    final row = await client.rpc(
      'bestie_submit_nca_v4',
      params: {
        'p_session_id': sessionId,
        'p_name': name.trim(),
        'p_city': city.trim(),
        'p_animal': animal.trim(),
        'p_plant': plant.trim(),
        'p_thing': thing.trim(),
        'p_country': country.trim(),
      },
    );
    return _state(row);
  }

  Future<NameCityAnimalState> expireRound(String sessionId) async {
    _requireUserId();
    final row = await client.rpc(
      'bestie_expire_nca_v4',
      params: {'p_session_id': sessionId},
    );
    return _state(row);
  }

  Future<NameCityAnimalState> review({
    required String sessionId,
    required Map<String, bool> reviews,
  }) async {
    _requireUserId();
    bool value(String key) => reviews[key] == true;

    final row = await client.rpc(
      'bestie_review_nca_v4',
      params: {
        'p_session_id': sessionId,
        'p_name_review': value('name'),
        'p_city_review': value('city'),
        'p_animal_review': value('animal'),
        'p_plant_review': value('plant'),
        'p_thing_review': value('thing'),
        'p_country_review': value('country'),
      },
    );
    return _state(row);
  }

  Future<NameCityAnimalState> surrender(String sessionId) async {
    _requireUserId();
    final row = await client.rpc(
      'bestie_surrender_nca_v4',
      params: {'p_session_id': sessionId},
    );
    return _state(row);
  }

  Future<void> notifyPartner({
    required String partnerId,
    required String action,
    required String sessionId,
  }) async {
    try {
      await NotificationService(client).create(
        userId: partnerId,
        title: 'İsim Şehir Hayvan',
        body: 'Oyunun durumu güncellendi.',
        type: 'game',
        data: {
          'action': action,
          'game_type': 'name_city_animal',
          'session_id': sessionId,
          'event_key': 'nca:$sessionId:$action:${client.auth.currentUser?.id}',
        },
      );
    } catch (e) {
      debugPrint('NCA notification skipped: $e');
    }
  }

  Stream<NameCityAnimalState> watchState(String sessionId) {
    RealtimeChannel? channel;
    late final StreamController<NameCityAnimalState> controller;
    var active = true;

    Future<void> emit() async {
      if (!active || controller.isClosed) return;
      try {
        final state = await getState(sessionId);
        if (active && !controller.isClosed) controller.add(state);
      } catch (error, stackTrace) {
        if (active && !controller.isClosed) controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<NameCityAnimalState>(
      sync: false,
      onListen: () {
        if (client.auth.currentUser == null) {
          controller.addError(const AuthException('Authentication required'));
          return;
        }

        final realtimeChannel = client.channel('bestie-nca-v4-$sessionId');
        channel = realtimeChannel;
        realtimeChannel
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'name_city_animal_games',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'session_id',
                value: sessionId,
              ),
              callback: (_) => unawaited(emit()),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'name_city_animal_answers',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'session_id',
                value: sessionId,
              ),
              callback: (_) => unawaited(emit()),
            )
            .subscribe((status, error) {
              if (!active || controller.isClosed) return;
              if (status == RealtimeSubscribeStatus.subscribed) {
                debugPrint('🟢 BESTIE NCA V4 SUBSCRIBED $sessionId');
                unawaited(emit());
              } else if (status == RealtimeSubscribeStatus.channelError ||
                  status == RealtimeSubscribeStatus.timedOut) {
                controller.addError(RealtimeSubscribeException(status, error));
              }
            });
      },
      onCancel: () async {
        active = false;
        final current = channel;
        channel = null;
        if (current != null) await client.removeChannel(current);
      },
    );

    return controller.stream;
  }

  NameCityAnimalState _state(dynamic value) {
    final row = value is Map
        ? Map<String, dynamic>.from(value)
        : value is List && value.isNotEmpty && value.first is Map
            ? Map<String, dynamic>.from(value.first as Map)
            : <String, dynamic>{};
    if (row.isEmpty) {
      throw const FormatException('Unexpected Name-City-Animal RPC response');
    }
    return NameCityAnimalState.fromMap(
      row,
      currentUserId: client.auth.currentUser?.id,
    );
  }
}
