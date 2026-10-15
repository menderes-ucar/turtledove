import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/game_answer_model.dart';
import '../models/game_question_model.dart';
import '../models/game_round_result_model.dart';
import '../models/game_session_model.dart';
import '../services/game_round_service.dart';
import '../services/game_session_service.dart';

class GameRoundProvider extends ChangeNotifier {
  final GameRoundService roundService;
  final GameSessionService sessionService;
  final String sessionId;
  final int initialRoundNumber;

  GameRound? _round;
  GameQuestion? _question;
  List<GameAnswer> _answers = const [];
  List<GameRoundResult> _results = const [];
  StreamSubscription<List<Map<String, dynamic>>>? _answersSubscription;
  StreamSubscription<GameSession>? _sessionSubscription;
  StreamSubscription<List<GamePlayer>>? _playersSubscription;
  bool _isAdvancing = false;
  bool _roundResolved = false;
  int? _nextRoundNumber;
  bool _gameCompleted = false;
  List<GamePlayer> _players = const [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isResolving = false;
  String? _error;

  GameRoundProvider({
    required this.roundService,
    required this.sessionService,
    required this.sessionId,
    required this.initialRoundNumber,
  }) {
    load();
  }

  String get currentSessionId => sessionId;
  int get roundNumber => initialRoundNumber;
  GameRound? get round => _round;
  GameQuestion? get question => _question;
  List<GameAnswer> get answers => List.unmodifiable(_answers);
  List<GameRoundResult> get results => List.unmodifiable(_results);
  List<GamePlayer> get players => List.unmodifiable(_players);
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;
  String? get currentUserId => sessionService.currentUserId;
  bool get hasCurrentUserAnswer => currentUserId != null &&
      _answers.any((answer) => answer.userId == currentUserId);
  bool get bothPlayersAnswered {
    if (_players.length != 2) return false;
    final playerIds = _players.map((player) => player.userId).toSet();
    return playerIds.length == 2 &&
        playerIds.every((userId) => _answers.any((answer) => answer.userId == userId));
  }
  bool get isAdvancing => _isAdvancing;
  bool get roundResolved => _roundResolved || _round?.resolvedAt != null;
  int? get nextRoundNumber => _nextRoundNumber;
  bool get gameCompleted => _gameCompleted;
  GamePlayer? get currentPlayer {
    final id = currentUserId;
    if (id == null) return null;
    for (final player in _players) {
      if (player.userId == id) return player;
    }
    return null;
  }
  bool get currentRoundConfirmed => currentPlayer?.roundConfirmed == true;
  bool get bothRoundConfirmed => _players.length == 2 && _players.every((p) => p.roundConfirmed);
  GameAnswer? get currentUserAnswer {
    final id = currentUserId;
    if (id == null) return null;
    for (final answer in _answers) {
      if (answer.userId == id) return answer;
    }
    return null;
  }

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final round = await roundService.getCurrentRound(sessionId, initialRoundNumber);
      final question = await roundService.getQuestion(round.questionId);
      _round = round;
      _question = question;
      _roundResolved = round.resolvedAt != null;
      _nextRoundNumber = null;
      _gameCompleted = false;
      _results = const [];
      _players = await sessionService.getPlayers(sessionId);
      _listenToPlayers();
      _listenToAnswers(round.id);
      if (_roundResolved) {
        _results = await roundService.getRoundResults(round.id);
      }
      _listenToSession();
    } catch (error) {
      _error = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _listenToPlayers() {
    _playersSubscription?.cancel();
    _playersSubscription = sessionService.watchPlayers(sessionId).listen(
      (players) {
        _players = players;
        notifyListeners();
      },
      onError: (Object error) {
        // Keep the last known state; the session/answer streams remain usable.
        _error = error.toString();
        notifyListeners();
      },
    );
  }

  void _listenToAnswers(String roundId) {
    _answersSubscription?.cancel();
    _answersSubscription = sessionService.watchRoundAnswers(roundId).listen(
      (rows) {
        _answers = rows.map(GameAnswer.fromMap).toList(growable: false);
        _error = null;
        notifyListeners();
        if (bothPlayersAnswered && !roundResolved) {
          unawaited(resolveIfReady());
        }
      },
      onError: (Object error) {
        _error = error.toString();
        notifyListeners();
      },
    );
  }

  Future<void> submitAnswer(String answer) async {
    final round = _round;
    if (round == null || hasCurrentUserAnswer || _isSubmitting) return;
    final normalized = answer.trim();
    if (normalized.isEmpty) {
      _error = 'Cevap boş olamaz.';
      notifyListeners();
      return;
    }
    _isSubmitting = true;
    _error = null;
    notifyListeners();
    try {
      await sessionService.submitAnswer(roundId: round.id, answer: normalized);
    } catch (error) {
      _error = error.toString();
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> resolveIfReady() async {
    final currentRound = _round;
    if (currentRound == null || roundResolved || !bothPlayersAnswered || _isResolving) {
      return;
    }
    _isResolving = true;
    try {
      _round = await roundService.resolveIfReady(currentRound.id);
      _roundResolved = _round?.resolvedAt != null;
      if (_roundResolved) {
        _results = await roundService.getRoundResults(currentRound.id);
        _players = await sessionService.getPlayers(sessionId);
      }
      notifyListeners();
    } catch (error) {
      _error = error.toString();
      notifyListeners();
    } finally {
      _isResolving = false;
    }
  }

  void _listenToSession() {
    _sessionSubscription?.cancel();
    _sessionSubscription = sessionService.watchSession(sessionId).listen(
      (session) {
        if (session.status == 'completed') {
          _gameCompleted = true;
          notifyListeners();
          return;
        }
        if (session.status == 'playing' && session.currentRound > initialRoundNumber) {
          _nextRoundNumber = session.currentRound;
          notifyListeners();
        }
      },
      onError: (Object error) {
        _error = error.toString();
        notifyListeners();
      },
    );
  }

  Future<void> advanceToNextRound() async {
    final currentRound = _round;
    if (currentRound == null || !roundResolved || _isAdvancing) return;
    _isAdvancing = true;
    _error = null;
    notifyListeners();
    try {
      final session = await roundService.advanceToNextRound(
        sessionId: sessionId,
        roundId: currentRound.id,
      );
      _players = await sessionService.getPlayers(sessionId);
      if (session.status == 'completed') {
        _gameCompleted = true;
      } else if (session.currentRound > initialRoundNumber) {
        _nextRoundNumber = session.currentRound;
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      _isAdvancing = false;
      notifyListeners();
    }
  }

  Future<void> retry() => load();

  @override
  void dispose() {
    unawaited(_answersSubscription?.cancel());
    unawaited(_sessionSubscription?.cancel());
    unawaited(_playersSubscription?.cancel());
    super.dispose();
  }
}
