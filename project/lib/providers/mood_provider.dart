import 'package:flutter/material.dart';
import 'dart:async';
import '../models/mood_model.dart';
import '../services/mood_service.dart';

class MoodProvider extends ChangeNotifier {
  final MoodService moodService;
  final String userId;
  List<MoodEntry> _moods = [];
  Map<String, dynamic> _stats = {};
  StreamSubscription? _subscription;
  String? _streamError;

  MoodProvider({required this.moodService, required this.userId}) {
    _startListening();
    _loadStats();
  }

  List<MoodEntry> get moods => _moods;
  Map<String, dynamic> get stats => _stats;
  String? get streamError => _streamError;
  double get averageMood {
    final value = _stats['average'];
    if (value is num) return value.toDouble();
    return 0.0;
  }

  void _startListening() {
    _subscription = moodService.getMoodsStream(userId).listen(
      (newMoods) {
        _moods = newMoods;
        _streamError = null;
        notifyListeners();
      },
      onError: (error, stackTrace) {
        _streamError = error.toString();
        notifyListeners();
        debugPrint('🔴 MoodProvider stream error: $error');
      },
    );
  }

  Future<void> _loadStats() async {
    try {
      _stats = await moodService.getMoodStats(userId);
    } catch (e) {
      _stats = {};
      debugPrint('🔴 MoodProvider._loadStats error: $e');
    }
    notifyListeners();
  }

  Future<void> addMood(int mood, {String? note, String? category}) async {
    await moodService.addMood(userId, mood, note: note, category: category);
    await _loadStats();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
