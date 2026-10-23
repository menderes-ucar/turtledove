import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../models/dove_deck_session.dart';
import '../../services/dove_deck_service.dart';

class DoveDeckLobbyScreen extends StatefulWidget {
  const DoveDeckLobbyScreen({super.key});
  @override
  State<DoveDeckLobbyScreen> createState() => _DoveDeckLobbyScreenState();
}

class _DoveDeckLobbyScreenState extends State<DoveDeckLobbyScreen> {
  late final DoveDeckService _service;
  DoveDeckSession? _game;
  StreamSubscription<DoveDeckSession>? _subscription;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = DoveDeckService(Supabase.instance.client);
  }

  Future<void> _invitePartner() async {
    final partnerId = context.read<AuthProvider>().profile?.pairedWith;
    if (partnerId == null || partnerId.isEmpty) {
      setState(() => _error = 'Önce partnerinle eşleşmelisin.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final game = await _service.createOrGetPartnerGame(partnerId);
      await _subscription?.cancel();
      _game = game;
      _subscription = _service.watch(game.id).listen((next) {
        if (mounted) setState(() => _game = next);
      }, onError: (Object error) {
        if (mounted) setState(() => _error = 'Canlı bağlantı kesildi. Bağlantını kontrol et.');
      });
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().profile;
    final paired = user?.pairedWith != null && user!.pairedWith!.isNotEmpty;
    final game = _game;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F2EC),
      appBar: AppBar(title: const Text('Dove Deck'), backgroundColor: const Color(0xFFF6F2EC)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF55466E), Color(0xFF8274A0)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.spa_rounded, color: Colors.white, size: 42),
                      SizedBox(height: 18),
                      Text('İkinize özel bir oyun.', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800)),
                      SizedBox(height: 8),
                      Text('Kartlarını hazırla, partnerini davet et ve sırayla oyna.', style: TextStyle(color: Colors.white70, height: 1.4)),
                    ]),
                  ),
                  const SizedBox(height: 22),
                  if (!paired) const Card(child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('Dove Deck oynamak için önce partnerinle eşleşmelisin.'),
                  )),
                  if (paired) FilledButton.icon(
                    onPressed: _loading ? null : _invitePartner,
                    icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.mark_email_read_outlined),
                    label: Text(game == null ? 'Partneri oyuna davet et' : 'Oyun odasına yeniden bağlan'),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: const Color(0xFF55466E)),
                  ),
                  if (_error != null) Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ),
                  if (game != null) Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Oyun odası hazır', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Text('Oda kodu: ${game.id.substring(0, 8).toUpperCase()}'),
                        const SizedBox(height: 6),
                        Text(game.isWaiting ? 'Partnerinin bağlanmasını bekliyor.' : game.isPlaying ? 'Oyun başladı.' : game.isFinished ? 'Oyun tamamlandı.' : 'Oda durumu: ${game.status}'),
                        const SizedBox(height: 8),
                        const Text('Bu aşamada oda ve canlı senkronizasyon altyapısı kuruluyor; kart hamleleri henüz etkinleştirilmedi.', style: TextStyle(color: Colors.black54)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
