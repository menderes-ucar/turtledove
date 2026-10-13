import 'dart:async';
import 'package:flutter/material.dart';
import '../models/pet_model.dart';
import '../services/pet_service.dart';

class PetProvider extends ChangeNotifier {
  final PetService service;
  final String userId;
  PetModel? _pet;
  StreamSubscription<PetModel?>? _subscription;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  PetProvider({required this.service, required this.userId}) {
    _load();
  }

  PetModel? get pet => _pet;
  bool get loading => _loading;
  bool get busy => _busy;
  String? get error => _error;

  Future<void> _load() async {
    try {
      _pet = await service.getPet(userId);
      _subscription = service.watchPet(userId).listen((value) {
        if (value != null) {
          _pet = value;
          notifyListeners();
        }
      }, onError: (Object error) {
        debugPrint('Pet realtime error: $error');
      });
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    try {
      final value = await service.getPet(userId);
      if (value != null) _pet = value;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> create({required String name, required String species, required String breed}) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _pet = await service.createPet(userId: userId, name: name, species: species, breed: breed);
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> action(String action) async {
    final current = _pet;
    if (current == null || _busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _pet = await service.performAction(userId: userId, petId: current.id, action: action);
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
