import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/dove_deck_rules.dart';
import '../../models/dove_deck_session.dart';
import '../../providers/auth_provider.dart';
import '../../services/dove_deck_service.dart';

class DoveDeckGameScreen extends StatefulWidget {
  const DoveDeckGameScreen({super.key, required this.gameId});
  final String gameId;
  @override
  State<DoveDeckGameScreen> createState() => _DoveDeckGameScreenState();
}

class _DoveDeckGameScreenState extends State<DoveDeckGameScreen> {
  late final DoveDeckService _service;
  DoveDeckSession? _session;
  DoveDeckRules? _rules;
  bool _busy = false;
  String? _error;
  StreamSubscription<DoveDeckSession>? _subscription;

  @override
  void initState() {
    super.initState();
    _service = DoveDeckService(Supabase.instance.client);
    _load();
    _subscription = _service.watch(widget.gameId).listen((next) {
      if (!mounted || _busy) return;
      setState(() {
        _session = next;
        _rules = next.isPlaying && next.state.isNotEmpty ? _decode(next.state) : null;
      });
    }, onError: (Object error) {
      // Mobile realtime can briefly reconnect; don't interrupt the game for a transient channel error.
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final row = await Supabase.instance.client.from('dove_deck_games').select().eq('id', widget.gameId).single();
      final session = DoveDeckSession.fromMap(row);
      if (!mounted) return;
      setState(() {
        _session = session;
        if (session.isPlaying && session.state.isNotEmpty) _rules = _decode(session.state);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  DoveDeckRules _decode(Map<String, dynamic> json) {
    final r = DoveDeckRules();
    List<DoveCard> cards(dynamic value) => (value as List? ?? const [])
        .map((e) => DoveCard.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    r.hands = [
      cards(json['hands'] is List && (json['hands'] as List).isNotEmpty ? json['hands'][0] : []),
      cards(json['hands'] is List && (json['hands'] as List).length > 1 ? json['hands'][1] : []),
    ];
    r.drawPile = cards(json['drawPile']);
    r.discardPile = cards(json['discardPile']);
    r.currentPlayer = (json['currentPlayer'] as num?)?.toInt() ?? 0;
    r.chosenSuit = json['chosenSuit'] == null ? null : DoveSuit.values.byName(json['chosenSuit'] as String);
    r.finished = json['finished'] == true;
    r.winner = (json['winner'] as num?)?.toInt();
    r.mustPassAfterDraw = json['mustPassAfterDraw'] == true;
    return r;
  }

  Map<String, dynamic> _encode(DoveDeckRules r) => {
    'hands': r.hands.map((h) => h.map((c) => c.toJson()).toList()).toList(),
    'drawPile': r.drawPile.map((c) => c.toJson()).toList(),
    'discardPile': r.discardPile.map((c) => c.toJson()).toList(),
    'currentPlayer': r.currentPlayer,
    'chosenSuit': r.chosenSuit?.name,
    'finished': r.finished,
    'winner': r.winner,
    'mustPassAfterDraw': r.mustPassAfterDraw,
  };

  Future<void> _start() async {
    final session = _session;
    if (session == null || _busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final rules = DoveDeckRules()..start();
      final next = await _service.start(session.id, _encode(rules));
      if (!mounted) return;
      setState(() { _rules = rules; _session = next; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveMove(void Function(DoveDeckRules) move) async {
    final session = _session;
    final current = _rules;
    if (session == null || current == null || _busy) return;
    if (session.currentTurn != Supabase.instance.client.auth.currentUser?.id) {
      setState(() => _error = "It's your partner's turn.");
      return;
    }
    final before = _encode(current);
    setState(() { _busy = true; _error = null; });
    try {
      move(current);
      final nextUser = current.finished
          ? session.currentTurn
          : (session.currentTurn == session.playerOne ? session.playerTwo : session.playerOne);
      final next = await _service.submitState(
        gameId: session.id,
        expectedVersion: session.version,
        state: _encode(current),
        nextTurn: nextUser,
        winner: current.finished
            ? (current.winner == 0 ? session.playerOne : session.playerTwo)
            : null,
      );
      if (!mounted) return;
      setState(() => _session = next);
    } catch (e) {
      if (mounted) {
        setState(() {
          _rules = _decode(before);
          _error = e.toString().contains('STALE_GAME_STATE')
              ? 'The game changed on the other device. Refreshing…'
              : e.toString();
        });
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _suitColor(DoveSuit? suit) => switch (suit) {
    DoveSuit.coral => const Color(0xFFE66D75),
    DoveSuit.ocean => const Color(0xFF3678C8),
    DoveSuit.leaf => const Color(0xFF39966B),
    DoveSuit.sun => const Color(0xFFE0A52F),
    null => const Color(0xFF55466E),
  };

  Future<DoveSuit?> _chooseSuit() async => showDialog<DoveSuit>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Choose a colour'),
      content: Wrap(spacing: 8, children: DoveSuit.values.map((s) => InkWell(
        onTap: () => Navigator.pop(ctx, s),
        child: CircleAvatar(backgroundColor: _suitColor(s), child: Text(['K','M','Y','S'][s.index], style: const TextStyle(color: Colors.white))),
      )).toList()),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final rules = _rules;
    final userId = context.watch<AuthProvider>().profile?.id ?? Supabase.instance.client.auth.currentUser?.id;
    if (session == null) return Scaffold(appBar: AppBar(title: const Text('DOVE DECK')), body: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!)));
    final myIndex = userId == session.playerOne ? 0 : 1;
    final myTurn = session.currentTurn == userId;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F2EC),
      appBar: AppBar(title: const Text('DOVE DECK'), backgroundColor: const Color(0xFFF6F2EC), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: SafeArea(child: rules == null
        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.style, size: 64, color: Color(0xFF55466E)),
            const SizedBox(height: 12),
            Text(session.isWaiting ? 'Your partner has been invited.' : 'GAME STATUS: ${session.status.toUpperCase()}', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (session.isWaiting) const Text(
              'Both players must tap Ready in the lobby before the match begins.',
              textAlign: TextAlign.center,
            ),
            if (session.isWaiting) FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to lobby'),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
          ])))
        : Column(children: [
          const SizedBox(height: 10),
          Text(session.isFinished ? (session.winner == userId ? 'YOU WIN! 🎉' : 'GAME OVER') : myTurn ? 'YOUR TURN' : "PARTNER'S TURN", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _pile('DRAW PILE', rules.drawPile.length, const Color(0xFF55466E)),
            const SizedBox(width: 18),
            _pile('DISCARD PILE', rules.discardPile.length, _suitColor(rules.topCard.suit), label: rules.topCard.label),
          ]),
          if (rules.chosenSuit != null) Padding(padding: const EdgeInsets.all(6), child: Text('Active colour: ${rules.chosenSuit!.name.toUpperCase()}')),
          if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 8),
          Text("PARTNER'S HAND  ·  ${rules.hands[1-myIndex].length} CARDS"),
          const Divider(),
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: rules.hands[myIndex].map((card) {
            final enabled = myTurn && !_busy && !session.isFinished && rules.currentPlayer == myIndex && rules.canPlay(card);
            return InkWell(
              onTap: enabled ? () async {
                DoveSuit? suit;
                if (card.isWild) { suit = await _chooseSuit(); if (suit == null || !mounted) return; }
                await _saveMove((r) => r.play(card.id, wildSuit: suit));
              } : null,
              child: Container(width: 66, height: 100, decoration: BoxDecoration(color: _suitColor(card.suit), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]), child: Center(child: Text(card.label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)))),
            );
          }).toList()))),
          Padding(padding: const EdgeInsets.all(14), child: Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: myTurn && !_busy && !rules.mustPassAfterDraw && !session.isFinished ? () => _saveMove((r) => r.draw()) : null, icon: const Icon(Icons.add), label: const Text('Draw card'))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(onPressed: myTurn && !_busy && rules.mustPassAfterDraw && !session.isFinished ? () => _saveMove((r) => r.pass()) : null, icon: const Icon(Icons.skip_next), label: const Text('Pass'))),
          ]),
          if (_busy) const LinearProgressIndicator(),
        ]),
      ),
    );
  }

  Widget _pile(String title, int count, Color color, {String? label}) => Column(children: [
    Container(width: 82, height: 112, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white, width: 2)), child: Center(child: Text(label ?? 'DOVE\n$count', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)))),
    const SizedBox(height: 5), Text('$title ($count)', style: const TextStyle(fontSize: 12)),
  ]);
}
