import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/game_question_model.dart';
import '../models/game_session_model.dart';
import '../models/game_round_result_model.dart';
import 'notification_service.dart';

class GameRoundService {
  final SupabaseClient client;
  final String languageCode;

  GameRoundService(this.client, {this.languageCode = 'en'});

  Future<GameRound> getCurrentRound(String sessionId, int roundNumber) async {
    _requireAuthenticatedUser();

    final row = await client
        .from('game_rounds')
        .select()
        .eq('session_id', sessionId)
        .eq('round_number', roundNumber)
        .single();

    return GameRound.fromMap(Map<String, dynamic>.from(row));
  }

  /// Loads only fields that are safe for the game client.
  /// The trivia correct answer must never be sent to the client.
  Future<GameQuestion> getQuestion(String questionId) async {
    _requireAuthenticatedUser();

    final response = await client.rpc(
      'get_game_question_public_localized',
      params: {
        'p_question_id': questionId,
        'p_language_code': languageCode,
      },
    );

    final row = _singleRpcRow(response);
    return GameQuestion.fromMap(row);
  }

  Future<GameQuestion> getCurrentQuestion({
    required String sessionId,
    required int roundNumber,
  }) async {
    final round = await getCurrentRound(sessionId, roundNumber);
    return getQuestion(round.questionId);
  }

  Map<String, dynamic> _singleRpcRow(dynamic response) {
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }

    if (response is List && response.isNotEmpty && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }

    throw const PostgrestException(
      message: 'Game question was not found',
    );
  }

  Future<List<GameRoundResult>> getRoundResults(String roundId) async {
    _requireAuthenticatedUser();
    final response = await client.rpc(
      'bestie_get_game_round_results_v3',
      params: {'p_round_id': roundId},
    );
    if (response is List) {
      return response
          .whereType<Map>()
          .map((row) => GameRoundResult.fromMap(Map<String, dynamic>.from(row)))
          .toList(growable: false);
    }
    return const [];
  }

  /// Advances the shared round through the server RPC. Question selection and
  /// pair-wide historical de-duplication are enforced atomically in Postgres;
  /// the client must not select or substitute a question locally.
  Future<GameSession> advanceToNextRound({
    required String sessionId,
    required String roundId,
  }) async {
    _requireAuthenticatedUser();
    final response = await client.rpc(
      'bestie_advance_game_round_v4',
      params: {
        'p_session_id': sessionId,
        'p_round_id': roundId,
      },
    );
    final row = _singleRpcRow(response);
    final session = GameSession.fromMap(row);

    // Confirmation is a partner-facing event. If this device is the first
    // confirmer, the other player gets a localized notification; the unique
    // event key prevents duplicate sends after a realtime reconnect.
    try {
      final me = client.auth.currentUser?.id;
      if (me != null) {
        final players = await client.rpc(
          'bestie_game_get_players_v3',
          params: {'p_session_id': sessionId},
        );
        if (players is List) {
          final partner = players
              .whereType<Map>()
              .map((p) => p['user_id']?.toString() ?? '')
              .firstWhere((id) => id.isNotEmpty && id != me, orElse: () => '');
          if (partner.isNotEmpty) {
            await NotificationService(client).create(
              userId: partner,
              title: 'Tur onayı',
              body: 'Partnerin turu onayladı.',
              type: 'game',
              data: {
                'action': 'round_confirmed',
                'game_type': session.gameType,
                'session_id': sessionId,
                'event_key': 'round-confirmed:$sessionId:$roundId:$me',
              },
            );
          }
        }
      }
    } catch (_) {}

    return session;
  }

  Future<GameRound> resolveIfReady(String roundId) async {
    _requireAuthenticatedUser();
    final response = await client.rpc(
      'bestie_resolve_game_round_v3',
      params: {'p_round_id': roundId},
    );
    if (response is Map) {
      return GameRound.fromMap(Map<String, dynamic>.from(response));
    }
    if (response is List && response.isNotEmpty && response.first is Map) {
      return GameRound.fromMap(Map<String, dynamic>.from(response.first as Map));
    }
    throw const PostgrestException(message: 'Round could not be resolved');
  }

  void _requireAuthenticatedUser() {
    final session = client.auth.currentSession;
    if (session == null ||
        session.accessToken.isEmpty ||
        client.auth.currentUser == null) {
      throw const AuthException('Game requires an active session');
    }
  }
}
