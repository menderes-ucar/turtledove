import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/game_session_model.dart';
import '../services/game_session_service.dart';

class GameSessionProvider extends ChangeNotifier {
  final GameSessionService service;
  final String gameType;
  final String partnerId;
  final int totalRounds;
  final List<String> categories;
  final GameSession? initialSession;

  GameSession? _session;
  List<GamePlayer> _players = const [];
  StreamSubscription<GameSession>? _sessionSubscription;
  StreamSubscription<List<GamePlayer>>? _playersSubscription;
  bool _isLoading = true;
  bool _isReadyLoading = false;
  bool _isStarting = false;
  String? _error;

  GameSessionProvider({
    required this.service,
    required this.gameType,
    required this.partnerId,
    this.totalRounds = 15,
    this.categories = const <String>[],
    this.initialSession,
  }) {
    _initialize();
  }

  GameSession? get session => _session;
  List<GamePlayer> get players => List.unmodifiable(_players);
  bool get isLoading => _isLoading;
  bool get isReadyLoading => _isReadyLoading;
  bool get isStarting => _isStarting;
  String? get error => _error;

  String? get currentUserId => service.currentUserId;

  GamePlayer? get currentPlayer {
    final userId = currentUserId;
    if (userId == null) return null;
    for (final player in _players) {
      if (player.userId == userId) return player;
    }
    return null;
  }

  bool get bothPlayersReady =>
      _players.length == 2 && _players.every((player) => player.ready);

  Future<void> _initialize() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final session = initialSession ??
          await service.createSession(
            gameType: gameType,
            partnerId: partnerId,
            totalRounds: totalRounds,
            categories: categories,
          );

      _session = session;
      _listenToSession(session.id);
      _listenToPlayers(session.id);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _listenToSession(String sessionId) {
    _sessionSubscription?.cancel();
    _sessionSubscription = service.watchSession(sessionId).listen(
      (session) {
        _session = session;
        _error = null;
        notifyListeners();
      },
      onError: (Object error) {
        _error = error.toString();
        notifyListeners();
      },
    );
  }

  void _listenToPlayers(String sessionId) {
    _playersSubscription?.cancel();
    _playersSubscription = service.watchPlayers(sessionId).listen(
      (players) {
        _players = players;
        _error = null;
        notifyListeners();
        if (bothPlayersReady) {
          unawaited(startIfReady());
        }
      },
      onError: (Object error) {
        _error = error.toString();
        notifyListeners();
      },
    );
  }

  Future<void> startIfReady() async {
    final sessionId = _session?.id;
    if (sessionId == null ||
        !_session!.isWaiting ||
        !bothPlayersReady ||
        _isStarting) {
      return;
    }

    _isStarting = true;
    _error = null;
    notifyListeners();

    try {
      _session = await service.startIfReady(sessionId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isStarting = false;
      notifyListeners();
    }
  }

  Future<void> toggleReady() async {
    final current = currentPlayer;
    final sessionId = _session?.id;
    if (current == null || sessionId == null || _isReadyLoading) return;

    _isReadyLoading = true;
    _error = null;
    notifyListeners();

    try {
      await service.setReady(sessionId, !current.ready);
      _players = await service.getPlayers(sessionId);
      notifyListeners();
      if (bothPlayersReady) {
        await startIfReady();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isReadyLoading = false;
      notifyListeners();
    }
  }

  Future<void> retry() async {
    await _cancelSubscriptions();
    _session = null;
    _players = const [];
    await _initialize();
  }

  Future<void> _cancelSubscriptions() async {
    await _sessionSubscription?.cancel();
    await _playersSubscription?.cancel();
    _sessionSubscription = null;
    _playersSubscription = null;
  }

  @override
  void dispose() {
    unawaited(_cancelSubscriptions());
    super.dispose();
  }
}
