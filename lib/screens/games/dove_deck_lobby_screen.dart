import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../models/dove_deck_session.dart';
import '../../models/dove_deck_rules.dart';
import '../../services/dove_deck_service.dart';
import 'dove_deck_game_screen.dart';

class DoveDeckLobbyScreen extends StatefulWidget {
  const DoveDeckLobbyScreen({super.key});
  @override
  State<DoveDeckLobbyScreen> createState() => _DoveDeckLobbyScreenState();
}

class _DoveDeckLobbyScreenState extends State<DoveDeckLobbyScreen> {
  late final DoveDeckService _service;
  DoveDeckSession? _game;
  StreamSubscription<DoveDeckSession>? _subscription;
  bool _loading = true;
  bool _actionBusy = false;
  bool _startingAutomatically = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = DoveDeckService(Supabase.instance.client);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreActiveGame());
  }

  Future<void> _restoreActiveGame() async {
    final partnerId = context.read<AuthProvider>().profile?.pairedWith;
    if (partnerId == null || partnerId.isEmpty) {
      if (mounted) setState(() { _loading = false; _error = 'Önce partnerinle eşleşmelisin.'; });
      return;
    }
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final game = await _service.findActiveGame(partnerId);
      if (!mounted) return;
      await _attachGame(game);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createGame() async {
    final partnerId = context.read<AuthProvider>().profile?.pairedWith;
    if (partnerId == null || partnerId.isEmpty) {
      setState(() => _error = 'Önce partnerinle eşleşmelisin.');
      return;
    }
    setState(() { _actionBusy = true; _error = null; });
    try {
      final game = await _service.createOrGetPartnerGame(partnerId);
      await _attachGame(game);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _attachGame(DoveDeckSession? game) async {
    await _subscription?.cancel();
    _subscription = null;
    if (game != null) {
      _game = game;
      _subscription = _service.watch(game.id).listen((next) {
        if (!mounted) return;
        setState(() => _game = next);
        _maybeAutoStart(next);
      }, onError: (Object e) {
        if (mounted) setState(() => _error = 'Canlı bağlantı kesildi. Yeniden dene.');
      });
    }
    if (mounted) setState(() => _game = game);
  }

  Future<void> _setReady(bool ready) async {
    final game = _game;
    if (game == null || _actionBusy) return;
    setState(() { _actionBusy = true; _error = null; });
    try {
      final updated = await _service.setReady(game.id, ready);
      if (mounted) setState(() => _game = updated);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _actionBusy = false);
        final latest = _game;
        if (latest != null) _maybeAutoStart(latest);
      }
    }
  }

  void _maybeAutoStart(DoveDeckSession game) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (!mounted || _actionBusy || _startingAutomatically ||
        !game.isWaiting || !game.bothReady || userId != game.playerOne) return;
    _startingAutomatically = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) { _startingAutomatically = false; return; }
      _startGame().whenComplete(() => _startingAutomatically = false);
    });
  }

  Future<void> _startGame() async {
    final game = _game;
    if (game == null || !game.bothReady || _actionBusy) return;
    setState(() { _actionBusy = true; _error = null; });
    try {
      final rules = DoveDeckRules()..start();
      final started = await _service.start(game.id, {
        'hands': rules.hands.map((h) => h.map((c) => c.toJson()).toList()).toList(),
        'drawPile': rules.drawPile.map((c) => c.toJson()).toList(),
        'discardPile': rules.discardPile.map((c) => c.toJson()).toList(),
        'currentPlayer': rules.currentPlayer,
        'chosenSuit': rules.chosenSuit?.name,
        'finished': rules.finished,
        'winner': rules.winner,
        'mustPassAfterDraw': rules.mustPassAfterDraw,
      });
      if (mounted) {
        setState(() => _game = started);
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => DoveDeckGameScreen(gameId: started.id)));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final partnerId = profile?.pairedWith;
    final paired = partnerId != null && partnerId.isNotEmpty;
    final game = _game;
    final iAmReady = game != null && userId != null && game.isReady(userId);
    final isCreator = game != null && userId == game.playerOne;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F2EC),
      appBar: AppBar(title: const Text('Dove Deck'), backgroundColor: const Color(0xFFF6F2EC),
        actions: [IconButton(tooltip: 'Devam eden oyunu yenile', onPressed: _loading ? null : _restoreActiveGame, icon: const Icon(Icons.refresh))]),
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF55466E), Color(0xFF8274A0)]),
              borderRadius: BorderRadius.circular(28)),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.style_rounded, color: Colors.white, size: 42), SizedBox(height: 14),
                Text('Dove Deck', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                SizedBox(height: 8),
                Text('Aynı maçta kalın. Hazır olduğunuzda birlikte başlayın.', style: TextStyle(color: Colors.white70)),
              ])),
            const SizedBox(height: 20),
            if (_loading) const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
            if (!paired && !_loading) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Dove Deck oynamak için önce partnerinle eşleşmelisin.'))),
            if (paired && !_loading && game == null) FilledButton.icon(
              onPressed: _actionBusy ? null : _createGame,
              icon: const Icon(Icons.add_circle_outline), label: const Text('Yeni oyun oluştur / partneri davet et')),
            if (game != null) Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(game.isPlaying ? 'Devam eden maç' : 'Bekleyen maç', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('Oda: ${game.id.substring(0, 8).toUpperCase()}'),
                Text(game.isPlaying ? 'Oyun sürüyor. Bu oturuma devam et.' : 'İkiniz de hazır olmadan maç başlamaz.'),
                const SizedBox(height: 12),
                if (game.isWaiting) ...[
                  Text('Senin durumun: ${iAmReady ? "Hazırsın" : "Henüz hazır değilsin"}'),
                  Text('Partnerin: ${game.isReady(userId == game.playerOne ? game.playerTwo : game.playerOne) ? "Hazır" : "Bekleniyor"}'),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: _actionBusy ? null : () => _setReady(!iAmReady),
                    child: Text(iAmReady ? 'Hazır değilim' : 'Hazırım')),
                  if (isCreator && !game.bothReady) const Text('Partnerin de hazır olduğunda oyun otomatik başlayacak.'),
                  if (isCreator && game.bothReady) const Text('İkiniz de hazırsınız. Oyun başlatılıyor…'),
                  if (!isCreator && game.bothReady) const Text('İkiniz de hazırsınız. Oyun otomatik başlayacak.'),
                ],
                if (game.isPlaying) FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DoveDeckGameScreen(gameId: game.id))),
                  icon: const Icon(Icons.play_arrow_rounded), label: const Text('Oyuna devam et')),
              ]))),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
          ],
        )),
      ))),
    );
  }
}
