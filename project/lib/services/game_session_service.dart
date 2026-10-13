import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/game_session_model.dart';
import 'notification_service.dart';

class GameSessionService {
  final SupabaseClient client;
  GameSessionService(this.client);

  static const allowedGameTypes = {
    'most_likely_to',
    'trivia',
    'word_game',
  };

  Future<GameSession> createSession({
    required String gameType,
    required String partnerId,
    int totalRounds = 15,
    List<String> categories = const <String>[],
  }) async {
    _requireAuthenticatedUser();
    final userId = client.auth.currentUser!.id;
    final normalizedType = gameType.trim().toLowerCase();

    if (!allowedGameTypes.contains(normalizedType)) {
      throw const FormatException('Invalid game type');
    }
    if (partnerId.trim().isEmpty || partnerId == userId) {
      throw const FormatException('Invalid partner');
    }
    if (totalRounds != 15) {
      throw const FormatException('Game always has exactly 15 questions');
    }

    final normalizedCategories = categories
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (normalizedCategories.isEmpty || normalizedCategories.length > 5) {
      throw const FormatException('Select between 1 and 5 categories');
    }

    final row = await client.rpc(
      'create_or_join_game_session',
      params: {
        'p_game_type': normalizedType,
        'p_partner_id': partnerId,
        'p_categories': normalizedCategories,
      },
    );

    final session = GameSession.fromMap(_singleRpcRow(row));
    try {
      await NotificationService(client).create(
        userId: partnerId,
        title: 'Yeni oyun daveti',
        body: normalizedType == 'trivia' ? 'Bilgi yarışmasına davet edildin.' : normalizedType == 'most_likely_to' ? 'En Çok Kim? oyununa davet edildin.' : 'Oyuna davet edildin.',
        type: 'game',
        data: {'game_type': normalizedType, 'session_id': session.id},
      );
    } catch (e) { debugPrint('Game notification skipped: $e'); }
    return session;
  }

  Future<GameSession> createWordGameSession({
    required String partnerId,
    required String languageCode,
  }) async {
    _requireAuthenticatedUser();
    final userId = client.auth.currentUser!.id;
    final language = languageCode.trim().toLowerCase();

    if (partnerId.trim().isEmpty || partnerId == userId) {
      throw const FormatException('Invalid partner');
    }

    if (!{'tr', 'en', 'de', 'es', 'fr'}.contains(language)) {
      throw const FormatException('Unsupported word game language');
    }

    final row = await client.rpc(
      'create_or_join_word_game_session',
      params: {
        'p_partner_id': partnerId,
        'p_language_code': language,
      },
    );

    final session = GameSession.fromMap(_singleRpcRow(row));
    try {
      await NotificationService(client).create(
        userId: partnerId,
        title: 'Yeni kelime oyunu',
        body: 'Kelime oyununa davet edildin.',
        type: 'game',
        data: {'game_type': 'word_game', 'session_id': session.id, 'language': language},
      );
    } catch (e) { debugPrint('Word game notification skipped: $e'); }
    return session;
  }

  Future<GameSession?> getActiveSession({
    required String gameType,
    required String partnerId,
  }) async {
    _requireAuthenticatedUser();
    final normalizedType = gameType.trim().toLowerCase();

    if (!allowedGameTypes.contains(normalizedType)) {
      throw const FormatException('Invalid game type');
    }
    if (partnerId.trim().isEmpty || partnerId == client.auth.currentUser!.id) {
      throw const FormatException('Invalid partner');
    }

    final row = await client.rpc(
      'get_active_game_session',
      params: {
        'p_game_type': normalizedType,
        'p_partner_id': partnerId,
      },
    );

    if (row == null || (row is List && row.isEmpty)) return null;
    return GameSession.fromMap(_singleRpcRow(row));
  }

  Future<GameSession> getSession(String sessionId) async {
    _requireAuthenticatedUser();

    final row = await client
        .from('game_sessions')
        .select()
        .eq('id', sessionId)
        .single();

    return GameSession.fromMap(Map<String, dynamic>.from(row));
  }

  Future<List<GamePlayer>> getPlayers(String sessionId) async {
    _requireAuthenticatedUser();

    final rows = await client
        .from('game_players')
        .select()
        .eq('session_id', sessionId)
        .order('joined_at');

    return rows
        .map((row) => GamePlayer.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Stream<GameSession> watchSession(String sessionId) {
    RealtimeChannel? channel;
    late final StreamController<GameSession> controller;
    var active = true;

    Future<void> emit() async {
      if (!active || controller.isClosed) return;
      try {
        final session = await getSession(sessionId);
        if (!active || controller.isClosed) return;
        controller.add(session);
      } catch (error, stackTrace) {
        if (!active || controller.isClosed) return;
        controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<GameSession>(
      sync: false,
      onListen: () {
        final currentUser = client.auth.currentUser;
        if (currentUser == null) {
          controller.addError(const AuthException('Game session requires an active session'));
          return;
        }

        final realtimeChannel = client.channel('bestie-game-session-$sessionId');
        channel = realtimeChannel;

        realtimeChannel
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'game_sessions',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'id',
                value: sessionId,
              ),
              callback: (_) => unawaited(emit()),
            )
            .subscribe((status, error) {
              if (!active || controller.isClosed) return;

              if (status == RealtimeSubscribeStatus.subscribed) {
                debugPrint('🟢 BESTIE GAME SESSION SUBSCRIBED $sessionId');
                unawaited(emit());
              } else if (status == RealtimeSubscribeStatus.channelError ||
                  status == RealtimeSubscribeStatus.timedOut) {
                debugPrint('🔴 BESTIE GAME SESSION status=$status error=$error');
                controller.addError(RealtimeSubscribeException(status, error));
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

  String? get currentUserId => client.auth.currentUser?.id;

  Stream<List<GamePlayer>> watchPlayers(String sessionId) {
    RealtimeChannel? channel;
    late final StreamController<List<GamePlayer>> controller;
    var active = true;

    Future<void> emit() async {
      if (!active || controller.isClosed) return;
      try {
        final players = await getPlayers(sessionId);
        if (!active || controller.isClosed) return;
        controller.add(players);
      } catch (error, stackTrace) {
        if (!active || controller.isClosed) return;
        controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<List<GamePlayer>>(
      sync: false,
      onListen: () {
        if (client.auth.currentUser == null) {
          controller.addError(
            const AuthException('Game session requires an active session'),
          );
          return;
        }

        final realtimeChannel = client.channel('bestie-game-players-$sessionId');
        channel = realtimeChannel;

        realtimeChannel
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'game_players',
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
                debugPrint('🟢 BESTIE GAME PLAYERS SUBSCRIBED $sessionId');
                unawaited(emit());
              } else if (status == RealtimeSubscribeStatus.channelError ||
                  status == RealtimeSubscribeStatus.timedOut) {
                debugPrint('🔴 BESTIE GAME PLAYERS status=$status error=$error');
                controller.addError(RealtimeSubscribeException(status, error));
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

  Future<GameSession> startIfReady(String sessionId) async {
    _requireAuthenticatedUser();

    final row = await client.rpc(
      'start_game_if_ready',
      params: {'p_session_id': sessionId},
    );

    return GameSession.fromMap(_singleRpcRow(row));
  }

  Future<void> setReady(String sessionId, bool ready) async {
    _requireAuthenticatedUser();
    final userId = client.auth.currentUser!.id;

    await client
        .from('game_players')
        .update({'ready': ready})
        .eq('session_id', sessionId)
        .eq('user_id', userId);

    if (ready) {
      try {
        final players = await getPlayers(sessionId);
        final partner = players.firstWhere(
          (player) => player.userId != userId,
          orElse: () => throw StateError('partner not found'),
        );
        await NotificationService(client).create(
          userId: partner.userId,
          title: 'Oyuncu hazır 🎮',
          body: 'Partnerin oyuna hazır. Sen de hazırsan başlayabilirsiniz.',
          type: 'game',
          data: {
            'action': 'player_ready',
            'session_id': sessionId,
            'event_key': 'ready:$sessionId:$userId',
          },
        );
      } catch (e) {
        debugPrint('Game ready notification skipped: $e');
      }
    }
  }

  Future<void> submitAnswer({
    required String roundId,
    required String answer,
  }) async {
    _requireAuthenticatedUser();
    final userId = client.auth.currentUser!.id;
    final normalizedAnswer = answer.trim();

    if (normalizedAnswer.isEmpty) {
      throw const FormatException('Answer cannot be empty');
    }

    await client.rpc(
      'submit_game_answer',
      params: {
        'p_round_id': roundId,
        'p_answer': normalizedAnswer,
      },
    );

    try {
      final round = await client.from('game_rounds').select('session_id,round_number').eq('id', roundId).maybeSingle();
      if (round != null) {
        final sessionId = round['session_id']?.toString();
        if (sessionId != null) {
          final players = await getPlayers(sessionId);
          final partner = players.firstWhere((p) => p.userId != userId, orElse: () => throw StateError('partner not found'));
          await NotificationService(client).create(
            userId: partner.userId,
            title: 'Oyunda sıra sende 🎮',
            body: 'Partnerin bu turu cevapladı. Senin cevabını bekliyor.',
            type: 'game',
            data: {'action': 'answer_submitted', 'session_id': sessionId, 'round_id': roundId, 'round': round['round_number']},
          );
        }
      }
    } catch (e) {
      debugPrint('Game answer notification skipped: $e');
    }
  }


  Stream<List<Map<String, dynamic>>> watchRoundAnswers(String roundId) {
    RealtimeChannel? channel;
    late final StreamController<List<Map<String, dynamic>>> controller;
    var active = true;

    Future<void> emit() async {
      if (!active || controller.isClosed) return;
      try {
        final rows = await client
            .from('game_answers')
            .select('round_id,user_id,answer,answered_at')
            .eq('round_id', roundId)
            .order('answered_at');
        if (!active || controller.isClosed) return;
        controller.add(rows.map((row) => Map<String, dynamic>.from(row)).toList());
      } catch (error, stackTrace) {
        if (!active || controller.isClosed) return;
        controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<List<Map<String, dynamic>>>(
      sync: false,
      onListen: () {
        if (client.auth.currentUser == null) {
          controller.addError(const AuthException('Game requires an active session'));
          return;
        }
        final realtimeChannel = client.channel('bestie-game-answers-$roundId');
        channel = realtimeChannel;
        realtimeChannel
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'game_answers',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'round_id',
                value: roundId,
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

  Map<String, dynamic> _singleRpcRow(dynamic response) {
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    if (response is List && response.isNotEmpty && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    throw const PostgrestException(message: 'Game session RPC returned no row');
  }

  void _requireAuthenticatedUser() {
    final session = client.auth.currentSession;
    if (session == null || session.accessToken.isEmpty || client.auth.currentUser == null) {
      throw const AuthException('Game session requires an active session');
    }
  }
}
