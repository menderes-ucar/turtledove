import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../localization/app_strings.dart';
import '../../providers/auth_provider.dart';
import '../../services/notification_service.dart';

class MemoryMatchScreen extends StatefulWidget {
  const MemoryMatchScreen({super.key});

  @override
  State<MemoryMatchScreen> createState() => _MemoryMatchScreenState();
}

class _MemoryMatchScreenState extends State<MemoryMatchScreen> {
  final SupabaseClient _client = Supabase.instance.client;

  RealtimeChannel? _channel;

  Map<String, dynamic>? _game;
  String? _sessionId;

  bool _loading = true;
  bool _busy = false;

  String? _error;

  String get _uid => _client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _start();
  }

  // ---------------------------------------------------------------------------
  // GAME START
  // ---------------------------------------------------------------------------

  Future<void> _start() async {
    final profile = context.read<AuthProvider>().profile;
    final partnerId = profile?.pairedWith;

    if (partnerId == null || partnerId.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
      return;
    }

    try {
      final response = await _client.rpc(
        'bestie_get_active_memory_match_v3',
        params: {
          'p_partner_id': partnerId,
        },
      );

      Map<String, dynamic>? existingGame;

      if (response is List && response.isNotEmpty) {
        existingGame = _toMap(response.first);
      } else if (response is Map && response.isNotEmpty) {
        existingGame = _toMap(response);
      }

      if (existingGame != null) {
        _game = existingGame;
      } else {
        final created = await _client.rpc(
          'bestie_create_memory_match_v3',
          params: {
            'p_partner_id': partnerId,
          },
        );

        _game = _extractRpcMap(created);

        await _notifyPartner(partnerId);
      }

      if (_game == null || _game!['id'] == null) {
        throw Exception('Memory Match session could not be created.');
      }

      _sessionId = _game!['id'].toString();

      _listen();
    } catch (e, stackTrace) {
      debugPrint('Memory Match start error: $e');
      debugPrintStack(stackTrace: stackTrace);

      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // NOTIFICATION
  // ---------------------------------------------------------------------------

  Future<void> _notifyPartner(String partnerId) async {
    try {
      final row = await _client
          .from('profiles')
          .select('language_code')
          .eq('id', partnerId)
          .maybeSingle();

      final rawLanguage = row?['language_code']?.toString().toLowerCase();

      final language = <String>{
        'tr',
        'en',
        'de',
        'es',
        'fr',
      }.contains(rawLanguage)
          ? rawLanguage!
          : 'en';

      const titles = <String, String>{
        'tr': 'Hafıza Eşleştirme 🧠',
        'en': 'Memory Match 🧠',
        'de': 'Memory-Spiel 🧠',
        'es': 'Parejas de memoria 🧠',
        'fr': 'Jeu de mémoire 🧠',
      };

      const bodies = <String, String>{
        'tr': 'Partnerin seninle hafıza oyunu oynamak için yeni bir oyun başlattı.',
        'en': 'Your partner started a new memory game with you.',
        'de': 'Dein Partner hat ein neues Memory-Spiel mit dir gestartet.',
        'es': 'Tu pareja ha iniciado un nuevo juego de memoria contigo.',
        'fr': 'Votre partenaire a commencé un nouveau jeu de mémoire avec vous.',
      };

      await NotificationService(_client).create(
        userId: partnerId,
        title: titles[language]!,
        body: bodies[language]!,
        type: 'game',
        data: {
          'game_type': 'memory_match',
          'action': 'open_game',
          'event_key': 'memory_match:$_sessionId',
        },
      );
    } catch (e, stackTrace) {
      debugPrint('Memory Match notification skipped: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  // ---------------------------------------------------------------------------
  // REALTIME
  // ---------------------------------------------------------------------------

  void _listen() {
    final sessionId = _sessionId;

    if (sessionId == null || sessionId.isEmpty) {
      return;
    }

    _channel = _client.channel('bestie-memory-$sessionId');

    _channel!
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'memory_match_sessions',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: sessionId,
      ),
      callback: (payload) {
        if (!mounted) {
          return;
        }

        if (payload.newRecord.isEmpty) {
          return;
        }

        setState(() {
          _game = Map<String, dynamic>.from(payload.newRecord);
        });
      },
    )
        .subscribe();
  }

  // ---------------------------------------------------------------------------
  // CARD TAP
  // ---------------------------------------------------------------------------

  Future<void> _tap(int index) async {
    if (_busy) {
      return;
    }

    final game = _game;

    if (game == null) {
      return;
    }

    if (game['status']?.toString() == 'completed') {
      return;
    }

    final turnUserId = game['turn_user_id']?.toString();

    if (turnUserId != _uid) {
      return;
    }

    final matchedIndices = _readIntList(
      game['matched_indices'],
    );

    final flippedIndices = _readIntList(
      game['flipped_indices'],
    );

    if (matchedIndices.contains(index)) {
      return;
    }

    if (flippedIndices.contains(index)) {
      return;
    }

    if (flippedIndices.length >= 2) {
      return;
    }

    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }

    try {
      final response = await _client.rpc(
        'bestie_memory_flip_v3',
        params: {
          'p_session_id': _sessionId,
          'p_index': index,
        },
      );

      final updatedGame = _extractRpcMap(response);

      if (updatedGame != null) {
        _game = updatedGame;
      }

      final currentFlipped = _readIntList(
        _game?['flipped_indices'],
      );

      if (currentFlipped.length == 2) {
        await Future<void>.delayed(
          const Duration(milliseconds: 850),
        );

        if (!mounted) {
          return;
        }

        final resolved = await _client.rpc(
          'bestie_memory_resolve_v3',
          params: {
            'p_session_id': _sessionId,
          },
        );

        final resolvedGame = _extractRpcMap(resolved);

        if (resolvedGame != null) {
          _game = resolvedGame;
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Memory Match tap error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  Map<String, dynamic>? _toMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return null;
  }

  Map<String, dynamic>? _extractRpcMap(dynamic response) {
    if (response is List && response.isNotEmpty) {
      return _toMap(response.first);
    }

    if (response is Map && response.isNotEmpty) {
      return _toMap(response);
    }

    return null;
  }

  List<int> _readIntList(dynamic value) {
    if (value is! List) {
      return <int>[];
    }

    return value
        .whereType<num>()
        .map((value) => value.toInt())
        .toList();
  }

  List<String> _readStringList(dynamic value) {
    if (value is! List) {
      return <String>[];
    }

    return value.map((value) => value.toString()).toList();
  }

  Map<String, dynamic> _readScores(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return <String, dynamic>{};
  }

  int _scoreFor(Map<String, dynamic> scores, String userId) {
    final value = scores[userId];

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _partnerScore(Map<String, dynamic> scores) {
    for (final entry in scores.entries) {
      if (entry.key != _uid) {
        return _scoreFor(
          scores,
          entry.key,
        );
      }
    }

    return 0;
  }

  // ---------------------------------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    final channel = _channel;

    if (channel != null) {
      unawaited(
        _client.removeChannel(channel),
      );
    }

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final profile = context.read<AuthProvider>().profile;

    final partnerId = profile?.pairedWith;

    if (partnerId == null || partnerId.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(strings.gameMemoryMatch),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              strings.pairFirst,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final game = _game;

    if (game == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(strings.gameMemoryMatch),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error ?? strings.gameLoadFailed,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final board = _readStringList(
      game['board'],
    );

    final flippedIndices = _readIntList(
      game['flipped_indices'],
    );

    final matchedIndices = _readIntList(
      game['matched_indices'],
    );

    final flipped = flippedIndices.toSet();
    final matched = matchedIndices.toSet();

    final scores = _readScores(
      game['scores'],
    );

    final myScore = _scoreFor(
      scores,
      _uid,
    );

    final partnerScore = _partnerScore(
      scores,
    );

    final turnUserId = game['turn_user_id']?.toString();

    final isMyTurn = turnUserId == _uid;

    final isCompleted =
        game['status']?.toString() == 'completed';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          strings.gameMemoryMatch,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          18,
          18,
          18,
          28,
        ),
        children: [
          // -------------------------------------------------------------------
          // STATUS / SCORE
          // -------------------------------------------------------------------

          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Text(
                    isCompleted
                        ? strings.gameCompleted
                        : isMyTurn
                        ? strings.memoryYourTurn
                        : strings.memoryPartnerTurn,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _ScoreCard(
                          label: strings.you,
                          score: myScore,
                          icon: Icons.person_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ScoreCard(
                          label: strings.partner,
                          score: partnerScore,
                          icon: Icons.favorite_rounded,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          // -------------------------------------------------------------------
          // ERROR
          // -------------------------------------------------------------------

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .errorContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onErrorContainer,
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],

          // -------------------------------------------------------------------
          // BOARD
          // -------------------------------------------------------------------

          if (board.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                strings.gameLoadFailed,
                textAlign: TextAlign.center,
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics:
              const NeverScrollableScrollPhysics(),
              itemCount: board.length,
              gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                final isVisible =
                    flipped.contains(index) ||
                        matched.contains(index);

                final canTap =
                    !_busy &&
                        !isCompleted &&
                        isMyTurn &&
                        !isVisible &&
                        flipped.length < 2;

                return AnimatedScale(
                  scale: isVisible ? 1.0 : 0.97,
                  duration:
                  const Duration(milliseconds: 160),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: canTap
                          ? () => _tap(index)
                          : null,
                      borderRadius:
                      BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration:
                        const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          color: isVisible
                              ? Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius:
                          BorderRadius.circular(16),
                          border: Border.all(
                            color: isVisible
                                ? Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: .35)
                                : Colors.transparent,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: AnimatedSwitcher(
                          duration: const Duration(
                            milliseconds: 150,
                          ),
                          child: Text(
                            isVisible
                                ? board[index]
                                : '?',
                            key: ValueKey(
                              '${index}_$isVisible',
                            ),
                            style: TextStyle(
                              fontSize:
                              isVisible ? 34 : 28,
                              fontWeight:
                              FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

          const SizedBox(height: 20),

          // -------------------------------------------------------------------
          // RULE
          // -------------------------------------------------------------------

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              strings.memoryRule,
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 12),

          // -------------------------------------------------------------------
          // CLOSE
          // -------------------------------------------------------------------

          TextButton.icon(
            onPressed: () => context.pop(),
            icon: const Icon(
              Icons.close_rounded,
            ),
            label: Text(
              strings.close,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SCORE CARD
// =============================================================================

class _ScoreCard extends StatelessWidget {
  final String label;
  final int score;
  final IconData icon;

  const _ScoreCard({
    required this.label,
    required this.score,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 22,
            color: scheme.primary,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            score.toString(),
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}