import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/word_game_model.dart';
import 'notification_service.dart';

class WordGameService {
  final SupabaseClient client;
  WordGameService(this.client);

  static const supportedLanguages = <String>{'tr', 'en', 'de', 'es', 'fr'};

  Future<WordGameState> startGame({
    required String sessionId,
    required String languageCode,
  }) async {
    _requireAuthenticatedUser();
    final language = languageCode.trim().toLowerCase();
    if (!supportedLanguages.contains(language)) {
      throw const FormatException('Unsupported word game language');
    }

    final row = await client.rpc(
      'start_word_game',
      params: {
        'p_session_id': sessionId,
        'p_language_code': language,
      },
    );
    return WordGameState.fromMap(_singleRow(row));
  }

  Future<WordGameState> getState(String sessionId) async {
    _requireAuthenticatedUser();
    final row = await client
        .from('game_word_sessions')
        .select()
        .eq('session_id', sessionId)
        .single();
    return WordGameState.fromMap(Map<String, dynamic>.from(row));
  }

  Future<List<WordGamePlay>> getPlays(String sessionId) async {
    _requireAuthenticatedUser();
    final rows = await client
        .from('game_word_plays')
        .select()
        .eq('session_id', sessionId)
        .order('turn_number');
    return rows
        .map((row) => WordGamePlay.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<WordGameState> submitWord({
    required String sessionId,
    required String word,
  }) async {
    _requireAuthenticatedUser();
    final value = word.trim();
    if (value.isEmpty) throw const FormatException('Word cannot be empty');

    debugPrint('🔤 BESTIE WORD SUBMIT session=$sessionId word="${value}"');

    try {
      final row = await client.rpc(
        'submit_word_game_word',
        params: {
          'p_session_id': sessionId,
          'p_word': value,
        },
      );

      debugPrint('🔤 BESTIE WORD RPC RESPONSE session=$sessionId row=$row');

      final state = WordGameState.fromMap(_singleRow(row));
      try {
        final me = client.auth.currentUser?.id;
        if (me != null) {
          final session = await client.from('game_sessions').select('created_by').eq('id', sessionId).maybeSingle();
          final players = await client.from('game_players').select('user_id').eq('session_id', sessionId);
          final partner = players.map((r) => r['user_id'].toString()).firstWhere((id) => id != me, orElse: () => '');
          if (partner.isNotEmpty) {
            final completed = state.isCompleted;
            final isMyTurn = state.turnUserId == partner;
            await NotificationService(client).create(
              userId: partner,
              title: completed ? 'Kelime oyunu bitti 🏆' : (isMyTurn ? 'Sıra sende 🔤' : 'Partnerin kelime oynadı'),
              body: completed ? 'Oyun tamamlandı.' : (state.lastWord ?? 'Partnerin hamlesini yaptı.'),
              type: 'game',
              data: {'action': completed ? 'game_completed' : 'turn_changed', 'session_id': sessionId, 'winner_user_id': state.winnerUserId ?? ''},
            );
          }
        }
      } catch (e) { debugPrint('Word game notification skipped: $e'); }
      debugPrint(
        '🔤 BESTIE WORD STATE '
        'language=${state.languageCode} '
        'required=${state.requiredLetter} '
        'turnUser=${state.turnUserId} '
        'turn=${state.turnNumber} '
        'status=${state.status} '
        'lastWord=${state.lastWord} '
        'lastError=${state.lastError}',
      );
      return state;
    } catch (error, stackTrace) {
      debugPrint('🔴 BESTIE WORD RPC ERROR session=$sessionId word="${value}" error=$error');
      debugPrint('$stackTrace');
      rethrow;
    }
  }

  Future<WordGameState> surrender({required String sessionId}) async {
    _requireAuthenticatedUser();
    final row = await client.rpc(
      'surrender_word_game',
      params: {'p_session_id': sessionId},
    );
    final state = WordGameState.fromMap(_singleRow(row));
    try {
      final me = client.auth.currentUser?.id;
      final players = await client.from('game_players').select('user_id').eq('session_id', sessionId);
      final partner = players.map((r) => r['user_id'].toString()).firstWhere((id) => id != me, orElse: () => '');
      if (partner.isNotEmpty) await NotificationService(client).create(userId: partner, title: 'Oyun sona erdi 🏆', body: 'Partnerin oyundan çıktı.', type: 'game', data: {'action': 'surrendered', 'session_id': sessionId});
    } catch (e) { debugPrint('Word surrender notification skipped: $e'); }
    return state;
  }

  Stream<WordGameState> watchState(String sessionId) {
    RealtimeChannel? channel;
    late final StreamController<WordGameState> controller;
    var active = true;

    Future<void> emit() async {
      if (!active || controller.isClosed) return;
      try {
        final state = await getState(sessionId);
        if (!active || controller.isClosed) return;
        controller.add(state);
      } catch (error, stackTrace) {
        if (!active || controller.isClosed) return;
        controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<WordGameState>(
      sync: false,
      onListen: () {
        if (client.auth.currentUser == null) {
          controller.addError(const AuthException('Word game requires an active session'));
          return;
        }
        final realtimeChannel = client.channel('bestie-word-game-state-$sessionId');
        channel = realtimeChannel;
        realtimeChannel
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'game_word_sessions',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'session_id',
                value: sessionId,
              ),
              callback: (_) => unawaited(emit()),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'game_word_plays',
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
                debugPrint('🟢 BESTIE WORD GAME SUBSCRIBED $sessionId');
                unawaited(emit());
              } else if (status == RealtimeSubscribeStatus.channelError ||
                  status == RealtimeSubscribeStatus.timedOut) {
                controller.addError(RealtimeSubscribeException(status, error));
              }
            });
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

  Stream<List<WordGamePlay>> watchPlays(String sessionId) {
    RealtimeChannel? channel;
    late final StreamController<List<WordGamePlay>> controller;
    var active = true;

    Future<void> emit() async {
      if (!active || controller.isClosed) return;
      try {
        final plays = await getPlays(sessionId);
        if (!active || controller.isClosed) return;
        controller.add(plays);
      } catch (error, stackTrace) {
        if (!active || controller.isClosed) return;
        controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<List<WordGamePlay>>(
      sync: false,
      onListen: () {
        if (client.auth.currentUser == null) {
          controller.addError(const AuthException('Word game requires an active session'));
          return;
        }
        final realtimeChannel = client.channel('bestie-word-game-plays-$sessionId');
        channel = realtimeChannel;
        realtimeChannel
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'game_word_plays',
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
                unawaited(emit());
              } else if (status == RealtimeSubscribeStatus.channelError ||
                  status == RealtimeSubscribeStatus.timedOut) {
                controller.addError(RealtimeSubscribeException(status, error));
              }
            });
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

  void _requireAuthenticatedUser() {
    if (client.auth.currentUser == null) {
      throw const AuthException('Authentication required');
    }
  }

  Map<String, dynamic> _singleRow(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    throw const FormatException('Unexpected RPC response');
  }
}
