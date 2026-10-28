import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dove_deck_session.dart';
import 'notification_service.dart';

class DoveDeckService {
  DoveDeckService(this.client);
  final SupabaseClient client;

  String get _userId {
    final id = client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Kart oyunu için oturum açmalısın.');
    return id;
  }

  /// Returns the existing active room, or creates one if none exists.
  /// Notification is sent only when this call appears to have created a new room.
  Future<DoveDeckSession> createOrGetPartnerGame(String partnerId) async {
    final userId = _userId;
    final existing = await findActiveGame(partnerId);
    final row = await client.rpc('dove_deck_create_game', params: {'p_partner_id': partnerId});
    final game = DoveDeckSession.fromMap(_one(row));
    if (existing == null) {
      try {
        await NotificationService(client).create(
          userId: partnerId,
          title: 'Yeni Dove Deck daveti 🃏',
          body: 'Partnerin Dove Deck oynamaya davet ediyor.',
          type: 'game',
          data: {'game_type': 'dove_deck', 'game_id': game.id, 'action': 'dove_deck_invite'},
        );
      } catch (_) {}
    }
    return game;
  }

  /// The lobby calls this on every entry. It never creates a game.
  Future<DoveDeckSession?> findActiveGame(String partnerId) async {
    final userId = _userId;
    final rows = await client.from('dove_deck_games').select()
      .inFilter('status', ['waiting', 'playing'])
      .or('and(player_one.eq.$userId,player_two.eq.$partnerId),and(player_one.eq.$partnerId,player_two.eq.$userId)')
      .order('updated_at', ascending: false)
      .limit(1);
    if (rows is List && rows.isNotEmpty) {
      return DoveDeckSession.fromMap(Map<String, dynamic>.from(rows.first as Map));
    }
    return null;
  }

  Future<DoveDeckSession> setReady(String gameId, bool ready) async {
    _userId;
    final row = await client.rpc('dove_deck_set_ready', params: {
      'p_game_id': gameId,
      'p_ready': ready,
    });
    return DoveDeckSession.fromMap(_one(row));
  }

  Future<DoveDeckSession> start(String gameId, Map<String, dynamic> initialState) async {
    _userId;
    final row = await client.rpc('dove_deck_start_game', params: {
      'p_game_id': gameId,
      'p_initial_state': initialState,
    });
    return DoveDeckSession.fromMap(_one(row));
  }

  Future<DoveDeckSession> submitState({
    required String gameId,
    required int expectedVersion,
    required Map<String, dynamic> state,
    required String nextTurn,
    String? winner,
  }) async {
    _userId;
    final row = await client.rpc('dove_deck_submit_state', params: {
      'p_game_id': gameId,
      'p_expected_version': expectedVersion,
      'p_state': state,
      'p_next_turn': nextTurn,
      'p_winner': winner,
    });
    return DoveDeckSession.fromMap(_one(row));
  }

  Stream<DoveDeckSession> watch(String gameId) {
    late final StreamController<DoveDeckSession> controller;
    RealtimeChannel? channel;
    var active = true;
    Future<void> refresh() async {
      if (!active || controller.isClosed) return;
      try {
        final row = await client.from('dove_deck_games').select().eq('id', gameId).single();
        if (active && !controller.isClosed) controller.add(DoveDeckSession.fromMap(row));
      } catch (error, stack) {
        if (active && !controller.isClosed) controller.addError(error, stack);
      }
    }
    controller = StreamController<DoveDeckSession>(
      onListen: () {
        _userId;
        final c = client.channel('dove-deck-$gameId');
        channel = c;
        c.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'dove_deck_games',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: gameId),
          callback: (_) => unawaited(refresh()),
        ).subscribe((status, error) {
          if (!active || controller.isClosed) return;
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(refresh());
          } else if (status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.timedOut) {
            controller.addError(RealtimeSubscribeException(status, error));
          }
        });
      },
      onCancel: () async {
        active = false;
        final c = channel;
        channel = null;
        if (c != null) await client.removeChannel(c);
      },
    );
    return controller.stream;
  }

  Map<String, dynamic> _one(dynamic row) {
    if (row is Map) return Map<String, dynamic>.from(row);
    if (row is List && row.isNotEmpty && row.first is Map) return Map<String, dynamic>.from(row.first as Map);
    throw const PostgrestException(message: 'Dove Deck RPC returned no game');
  }
}
