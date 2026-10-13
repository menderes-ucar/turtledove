import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/game_session_model.dart';
import '../models/word_game_model.dart';
import '../services/game_session_service.dart';
import '../services/word_game_service.dart';

class WordGameProvider extends ChangeNotifier {
  final GameSessionService sessionService;
  final WordGameService wordService;
  final String partnerId;
  final String languageCode;
  final GameSession? initialSession;

  GameSession? _session;
  WordGameState? _state;
  List<GamePlayer> _players = const [];
  List<WordGamePlay> _plays = const [];
  StreamSubscription<GameSession>? _sessionSub;
  StreamSubscription<List<GamePlayer>>? _playersSub;
  StreamSubscription<WordGameState>? _stateSub;
  StreamSubscription<List<WordGamePlay>>? _playsSub;
  bool _loading = true;
  bool _readyLoading = false;
  bool _starting = false;
  bool _submitting = false;
  String? _error;

  WordGameProvider({
    required this.sessionService,
    required this.wordService,
    required this.partnerId,
    required this.languageCode,
    this.initialSession,
  }) {
    _initialize();
  }

  GameSession? get session => _session;
  WordGameState? get state => _state;
  List<GamePlayer> get players => List.unmodifiable(_players);
  List<WordGamePlay> get plays => List.unmodifiable(_plays);
  bool get isLoading => _loading;
  bool get isReadyLoading => _readyLoading;
  bool get isStarting => _starting;
  bool get isSubmitting => _submitting;
  String? get error => _error;
  String? get currentUserId => sessionService.currentUserId;

  GamePlayer? get currentPlayer {
    final id = currentUserId;
    if (id == null) return null;
    for (final player in _players) {
      if (player.userId == id) return player;
    }
    return null;
  }

  bool get bothPlayersReady =>
      _players.length == 2 && _players.every((player) => player.ready);

  bool get myTurn => _state?.turnUserId == currentUserId;

  Future<void> _initialize() async {
    _loading = true;
    notifyListeners();
    try {
      _session = initialSession ??
          await sessionService.createWordGameSession(
            partnerId: partnerId,
            languageCode: languageCode,
          );
      _listenSession(_session!.id);
      _listenPlayers(_session!.id);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _listenSession(String id) {
    _sessionSub?.cancel();
    _sessionSub = sessionService.watchSession(id).listen(
      (value) {
        _session = value;
        _error = null;
        notifyListeners();
        if (value.isPlaying && _state == null) _listenWordGame(value.id);
      },
      onError: (Object error) {
        _error = error.toString();
        notifyListeners();
      },
    );
  }

  void _listenPlayers(String id) {
    _playersSub?.cancel();
    _playersSub = sessionService.watchPlayers(id).listen(
      (value) {
        _players = value;
        notifyListeners();
        if (bothPlayersReady && _session?.isWaiting == true) {
          unawaited(startIfReady());
        }
      },
      onError: (Object error) {
        _error = error.toString();
        notifyListeners();
      },
    );
  }

  Future<void> toggleReady() async {
    final player = currentPlayer;
    final id = _session?.id;
    if (player == null || id == null || _readyLoading) return;
    _readyLoading = true;
    _error = null;
    notifyListeners();
    try {
      await sessionService.setReady(id, !player.ready);
    } catch (e) {
      _error = e.toString();
    } finally {
      _readyLoading = false;
      notifyListeners();
    }
  }

  Future<void> startIfReady() async {
    final id = _session?.id;
    if (id == null || !bothPlayersReady || !_session!.isWaiting || _starting) return;
    _starting = true;
    notifyListeners();
    try {
      _state = await wordService.startGame(
        sessionId: id,
        languageCode: languageCode,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  void _listenWordGame(String id) {
    _stateSub?.cancel();
    _playsSub?.cancel();
    _stateSub = wordService.watchState(id).listen(
      (value) {
        _state = value;
        _error = null;
        notifyListeners();
      },
      onError: (Object error) {
        _error = error.toString();
        notifyListeners();
      },
    );
    _playsSub = wordService.watchPlays(id).listen(
      (value) {
        _plays = value;
        notifyListeners();
      },
      onError: (Object error) {
        _error = error.toString();
        notifyListeners();
      },
    );
  }

  Future<void> submitWord(String word) async {
    final id = _session?.id;
    if (id == null || !myTurn || _submitting) return;
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      _state = await wordService.submitWord(sessionId: id, word: word);
      if (_state?.lastErrorUserId == currentUserId) {
        _error = _state?.lastError;
      } else {
        _error = null;
      }
      _listenWordGame(id);
    } catch (e) {
      _error = e.toString();
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  Future<void> surrender() async {
    final id = _session?.id;
    if (id == null || _state == null || _state!.isCompleted) return;
    _error = null;
    notifyListeners();
    try {
      _state = await wordService.surrender(sessionId: id);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> retry() async {
    await _cancelSubscriptions();
    _session = null;
    _state = null;
    _players = const [];
    _plays = const [];
    _error = null;
    await _initialize();
  }

  Future<void> _cancelSubscriptions() async {
    await _sessionSub?.cancel();
    await _playersSub?.cancel();
    await _stateSub?.cancel();
    await _playsSub?.cancel();
    _sessionSub = null;
    _playersSub = null;
    _stateSub = null;
    _playsSub = null;
  }

  @override
  void dispose() {
    unawaited(_cancelSubscriptions());
    super.dispose();
  }
}
