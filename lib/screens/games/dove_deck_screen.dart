import 'package:flutter/material.dart';
import '../../models/dove_deck_game.dart';

class DoveDeckScreen extends StatefulWidget {
  const DoveDeckScreen({super.key});

  @override
  State<DoveDeckScreen> createState() => _DoveDeckScreenState();
}

class _DoveDeckScreenState extends State<DoveDeckScreen> {
  late DoveDeckGame game;
  String? message;

  @override
  void initState() {
    super.initState();
    _newGame();
  }

  void _newGame() {
    game = DoveDeckGame()..start();
    message = 'Sıra sende. Üstteki kartın rengine veya numarasına uyan bir kart oyna.';
  }

  Color _color(DoveSuit? suit) => switch (suit) {
    DoveSuit.coral => const Color(0xFFE65B67),
    DoveSuit.ocean => const Color(0xFF3288C7),
    DoveSuit.leaf => const Color(0xFF319B75),
    DoveSuit.sun => const Color(0xFFF0B93E),
    null => const Color(0xFF564A75),
  };

  String _suitName(DoveSuit suit) => switch (suit) {
    DoveSuit.coral => 'Mercan',
    DoveSuit.ocean => 'Okyanus',
    DoveSuit.leaf => 'Yaprak',
    DoveSuit.sun => 'Güneş',
  };

  Future<DoveSuit?> _chooseSuit() => showModalBottomSheet<DoveSuit>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: DoveSuit.values.map((suit) => FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _color(suit)),
            onPressed: () => Navigator.pop(context, suit),
            child: Text(_suitName(suit)),
          )).toList(),
        ),
      ),
    ),
  );

  Future<void> _play(DoveCard card) async {
    try {
      final suit = card.isWild ? await _chooseSuit() : null;
      if (card.isWild && suit == null) return;
      setState(() {
        game.play(card, wildSuit: suit);
        message = game.finished
          ? (game.winner == 0 ? 'Kazandın! 🕊️' : 'Rakip kazandı.')
          : game.currentPlayer == 0 ? 'Sıra sende.' : 'Rakip düşünüyor…';
      });
      if (!game.finished && game.currentPlayer == 1) _botTurn();
    } catch (e) {
      setState(() => message = e.toString().replaceFirst('Bad state: ', ''));
    }
  }

  void _botTurn() {
    Future<void>.delayed(const Duration(milliseconds: 650), () {
      if (!mounted || game.finished || game.currentPlayer != 1) return;
      setState(() {
        final options = game.currentHand.where(game.canPlay).toList();
        if (options.isEmpty) {
          game.draw();
          game.passAfterDraw();
          message = 'Rakip kart çekti. Sıra sende.';
        } else {
          final card = options.first;
          game.play(card, wildSuit: card.isWild ? DoveSuit.values[DateTime.now().millisecond % 4] : null);
          message = game.finished ? 'Rakip kazandı.' : 'Rakip oynadı. Sıra sende.';
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F1EB),
      appBar: AppBar(
        title: const Text('Dove Deck', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: const Color(0xFFF5F1EB),
        actions: [IconButton(onPressed: () => setState(_newGame), icon: const Icon(Icons.refresh), tooltip: 'Yeni oyun')],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(children: [
                const CircleAvatar(backgroundColor: Color(0xFF564A75), child: Icon(Icons.smart_toy_outlined, color: Colors.white)),
                const SizedBox(width: 10),
                const Expanded(child: Text('Rakip', style: TextStyle(fontWeight: FontWeight.w700))),
                Text('${game.hands[1].length} kart', style: theme.textTheme.bodySmall),
              ]),
            ),
            SizedBox(
              height: 48,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: game.hands[1].length,
                itemBuilder: (_, __) => Container(
                  width: 27, margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(color: const Color(0xFF564A75), borderRadius: BorderRadius.circular(7), border: Border.all(color: Colors.white, width: 1.5)),
                  child: const Center(child: Icon(Icons.spa, size: 14, color: Colors.white70)),
                ),
              ),
            ),
            const Spacer(),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _card(game.topCard, large: true),
              const SizedBox(width: 18),
              Column(children: [
                const Icon(Icons.spa, size: 28, color: Color(0xFF564A75)),
                const SizedBox(height: 5),
                Text(game.chosenSuit == null ? 'Masa' : _suitName(game.chosenSuit!), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ]),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(message ?? '', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: game.currentPlayer == 0 && !game.finished && !game.mustDraw ? () {
                    setState(() { game.draw(); message = 'Kart çektin. Sırayı geçirmek için “Pas”a bas.'; });
                  } : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Kart çek'),
                )),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(
                  onPressed: game.currentPlayer == 0 && game.mustDraw && !game.finished ? () {
                    setState(() { game.passAfterDraw(); message = 'Sıra rakipte.'; });
                    _botTurn();
                  } : null,
                  child: const Text('Pas geç'),
                )),
              ]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 156,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                itemCount: game.hands[0].length,
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemBuilder: (_, index) {
                  final card = game.hands[0][index];
                  final playable = game.currentPlayer == 0 && game.canPlay(card);
                  return GestureDetector(
                    onTap: playable ? () => _play(card) : null,
                    child: Opacity(opacity: playable ? 1 : 0.58, child: _card(card)),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Row(children: [
                const Expanded(child: Text('Sen', style: TextStyle(fontWeight: FontWeight.w800))),
                Text('${game.hands[0].length} kart'),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(DoveCard card, {bool large = false}) {
    final color = _color(card.suit);
    return Container(
      width: large ? 92 : 84,
      height: large ? 136 : 132,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 7, offset: Offset(0, 3))],
      ),
      child: Stack(children: [
        Positioned(left: 8, top: 7, child: Text(card.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
        Center(child: Transform.rotate(
          angle: -0.18,
          child: Container(
            width: large ? 68 : 60,
            height: large ? 88 : 78,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(50)),
            child: Center(child: Text(card.label, style: TextStyle(color: color, fontSize: card.label.length > 2 ? 16 : 28, fontWeight: FontWeight.w900))),
          ),
        )),
        Positioned(right: 8, bottom: 7, child: Text(card.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
      ]),
    );
  }
}
