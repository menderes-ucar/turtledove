import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/name_city_animal_model.dart';
import '../../services/name_city_animal_service.dart';


class NameCityAnimalProvider extends ChangeNotifier {
  final NameCityAnimalService service;
  final String partnerId;
  final String languageCode;
  final String? initialSessionId;

  NameCityAnimalState? _state;
  StreamSubscription<NameCityAnimalState>? _subscription;
  Timer? _ticker;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  NameCityAnimalProvider({
    required this.service,
    required this.partnerId,
    required this.languageCode,
    this.initialSessionId,
  }) {
    _initialize();
  }

  NameCityAnimalState? get state => _state;
  bool get isLoading => _loading;
  bool get isBusy => _busy;
  String? get error => _error;
  String? get currentUserId => service.client.auth.currentUser?.id;

  bool get myReady {
    final s = _state;
    if (s == null) return false;
    return currentUserId == s.createdBy ? s.createdReady : s.partnerReady;
  }

  bool get myTurnToSubmit => _state?.isAnswering == true && !_state!.submittedByMe;
  bool get myReviewComplete => _state?.myReviewComplete == true;

  Duration get remaining {
    final deadline = _state?.roundDeadlineAt;
    if (deadline == null) return Duration.zero;
    final seconds = deadline.difference(DateTime.now()).inSeconds;
    return Duration(seconds: seconds.clamp(0, 9999).toInt());
  }

  Future<void> _initialize() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _state = initialSessionId == null
          ? await service.createOrJoin(
              partnerId: partnerId,
              languageCode: languageCode,
            )
          : await service.getState(initialSessionId!);
      _listen();
      _restartTicker();
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _listen() {
    final sessionId = _state?.sessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    _subscription?.cancel();
    _subscription = service.watchState(sessionId).listen(
      (state) {
        _state = state;
        _error = null;
        _restartTicker();
        notifyListeners();
      },
      onError: (Object error) {
        _error = error.toString();
        notifyListeners();
      },
    );
  }

  void _restartTicker() {
    _ticker?.cancel();
    if (_state?.isAnswering != true) return;

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_state?.isAnswering != true) {
        _ticker?.cancel();
        return;
      }
      notifyListeners();
      if (remaining <= Duration.zero && !_busy) {
        _busy = true;
        try {
          _state = await service.expireRound(_state!.sessionId);
          _error = null;
          _listen();
          if (_state?.isReviewing == true && _state?.partnerId.isNotEmpty == true) {
            await service.notifyPartner(
              partnerId: _state!.partnerId,
              action: 'review_ready',
              sessionId: _state!.sessionId,
            );
          }
        } catch (error) {
          _error = error.toString();
        } finally {
          _busy = false;
          notifyListeners();
        }
      }
    });
  }

  Future<void> toggleReady() async {
    final state = _state;
    if (state == null || !state.isWaiting || _busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _state = await service.setReady(state.sessionId, !myReady);
      _listen();
      if (_state?.partnerId.isNotEmpty == true) {
        await service.notifyPartner(
          partnerId: _state!.partnerId,
          action: 'player_ready',
          sessionId: state.sessionId,
        );
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> submit({
    required String name,
    required String city,
    required String animal,
    required String plant,
    required String thing,
    required String country,
  }) async {
    final state = _state;
    if (state == null || !myTurnToSubmit || _busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _state = await service.submit(
        sessionId: state.sessionId,
        name: name,
        city: city,
        animal: animal,
        plant: plant,
        thing: thing,
        country: country,
      );
      _listen();
      if (_state?.partnerId.isNotEmpty == true) {
        await service.notifyPartner(
          partnerId: _state!.partnerId,
          action: 'answer_submitted',
          sessionId: state.sessionId,
        );
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> review(Map<String, bool> reviews) async {
    final state = _state;
    if (state == null || !state.isReviewing || myReviewComplete || _busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _state = await service.review(sessionId: state.sessionId, reviews: reviews);
      _listen();
      if (_state?.partnerId.isNotEmpty == true) {
        await service.notifyPartner(
          partnerId: _state!.partnerId,
          action: 'review_submitted',
          sessionId: state.sessionId,
        );
        if (_state!.roundNumber != state.roundNumber) {
          await service.notifyPartner(
            partnerId: _state!.partnerId,
            action: 'round_started',
            sessionId: _state!.sessionId,
          );
        }
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> surrender() async {
    final id = _state?.sessionId;
    if (id == null || _state?.isCompleted == true || _busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _state = await service.surrender(id);
      _listen();
    } catch (error) {
      _error = error.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> retry() async {
    await _subscription?.cancel();
    _subscription = null;
    _state = null;
    _error = null;
    await _initialize();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
