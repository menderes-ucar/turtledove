import 'package:flutter/material.dart';
import 'dart:async';
import '../models/countdown_model.dart';
import '../services/countdown_service.dart';

class CountdownProvider extends ChangeNotifier {
  final CountdownService countdownService;
  final String userId;
  List<Countdown> _countdowns = [];
  StreamSubscription? _subscription;
  Timer? _updateTimer;
  String? _streamError;

  CountdownProvider({required this.countdownService, required this.userId}) {
    _startListening();
    _startUpdateTimer();
  }

  List<Countdown> get countdowns => _countdowns;
  String? get streamError => _streamError;

  void _startListening() {
    _subscription = countdownService.getCountdownsStream(userId).listen(
      (newCountdowns) {
        _countdowns = newCountdowns;
        _streamError = null;
        notifyListeners();
      },
      onError: (error, stackTrace) {
        _streamError = error.toString();
        notifyListeners();
        debugPrint('🔴 CountdownProvider stream error: $error');
      },
    );
  }

  void _startUpdateTimer() {
    _updateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      notifyListeners(); // UI refresh for countdown display
    });
  }

  Future<void> addCountdown(String title, DateTime targetDate, String type, {String? emoji}) async {
    await countdownService.addCountdown(userId, title, targetDate, type, emoji: emoji);
  }

  Future<void> deleteCountdown(String countdownId) async {
    await countdownService.deleteCountdown(countdownId);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }
}
