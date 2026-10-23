import 'dart:math';

enum DoveSuit { coral, ocean, leaf, sun }
enum DoveCardKind { number, skip, reverse, drawTwo, wild, wildDrawFour }

class DoveCard {
  final String id;
  final DoveSuit? suit;
  final DoveCardKind kind;
  final int? number;

  const DoveCard({required this.id, required this.kind, this.suit, this.number});

  bool get isWild => suit == null;
  String get label => switch (kind) {
    DoveCardKind.number => '${number ?? 0}',
    DoveCardKind.skip => 'SKIP',
    DoveCardKind.reverse => '↺',
    DoveCardKind.drawTwo => '+2',
    DoveCardKind.wild => 'WILD',
    DoveCardKind.wildDrawFour => '+4',
  };
}

class DoveDeckGame {
  DoveDeckGame({Random? random}) : _random = random ?? Random();

  final Random _random;
  final List<List<DoveCard>> hands = [[], []];
  final List<DoveCard> drawPile = [];
  final List<DoveCard> discardPile = [];
  int currentPlayer = 0;
  int direction = 1;
  DoveSuit? chosenSuit;
  bool finished = false;
  int? winner;
  bool mustDraw = false;

  DoveCard get topCard => discardPile.last;
  List<DoveCard> get currentHand => hands[currentPlayer];

  void start() {
    hands[0].clear();
    hands[1].clear();
    drawPile.clear();
    discardPile.clear();
    currentPlayer = 0;
    direction = 1;
    chosenSuit = null;
    finished = false;
    winner = null;
    mustDraw = false;

    var serial = 0;
    for (final suit in DoveSuit.values) {
      for (var n = 0; n <= 9; n++) {
        drawPile.add(DoveCard(id: 'd${serial++}', suit: suit, kind: DoveCardKind.number, number: n));
        if (n != 0) {
          drawPile.add(DoveCard(id: 'd${serial++}', suit: suit, kind: DoveCardKind.number, number: n));
        }
      }
      for (final kind in [DoveCardKind.skip, DoveCardKind.reverse, DoveCardKind.drawTwo]) {
        for (var i = 0; i < 2; i++) {
          drawPile.add(DoveCard(id: 'd${serial++}', suit: suit, kind: kind));
        }
      }
    }
    for (var i = 0; i < 4; i++) {
      drawPile.add(DoveCard(id: 'd${serial++}', kind: DoveCardKind.wild));
      drawPile.add(DoveCard(id: 'd${serial++}', kind: DoveCardKind.wildDrawFour));
    }
    drawPile.shuffle(_random);
    for (var i = 0; i < 7; i++) {
      hands[0].add(drawPile.removeLast());
      hands[1].add(drawPile.removeLast());
    }
    do {
      final first = drawPile.removeLast();
      if (first.kind == DoveCardKind.number) {
        discardPile.add(first);
        break;
      }
      drawPile.insert(0, first);
    } while (drawPile.isNotEmpty);
  }

  bool canPlay(DoveCard card) {
    if (finished || !currentHand.any((c) => c.id == card.id)) return false;
    if (mustDraw) return false;
    if (card.isWild) return true;
    return card.suit == (chosenSuit ?? topCard.suit) ||
        (card.kind == DoveCardKind.number && card.number == topCard.number);
  }

  void draw() {
    if (finished || mustDraw) return;
    _drawTo(currentPlayer, 1);
    mustDraw = true;
  }

  void play(DoveCard card, {DoveSuit? wildSuit}) {
    if (!canPlay(card)) throw StateError('Bu kart şu anda oynanamaz.');
    if (card.isWild && wildSuit == null) throw ArgumentError('Joker için renk seçilmeli.');
    currentHand.removeWhere((c) => c.id == card.id);
    discardPile.add(card);
    chosenSuit = card.isWild ? wildSuit : null;
    if (currentHand.isEmpty) {
      finished = true;
      winner = currentPlayer;
      return;
    }
    switch (card.kind) {
      case DoveCardKind.skip:
      case DoveCardKind.reverse:
        direction *= -1; // With two players, reverse acts as a skip.
        currentPlayer = 1 - currentPlayer;
      case DoveCardKind.drawTwo:
        _drawTo(1 - currentPlayer, 2);
        currentPlayer = 1 - currentPlayer;
      case DoveCardKind.wildDrawFour:
        _drawTo(1 - currentPlayer, 4);
        currentPlayer = 1 - currentPlayer;
      default:
        currentPlayer = 1 - currentPlayer;
    }
    mustDraw = false;
  }

  void passAfterDraw() {
    if (!mustDraw || finished) throw StateError('Önce kart çekmelisin.');
    mustDraw = false;
    currentPlayer = 1 - currentPlayer;
  }

  void _drawTo(int player, int count) {
    for (var i = 0; i < count; i++) {
      if (drawPile.isEmpty) {
        if (discardPile.length <= 1) return;
        final top = discardPile.removeLast();
        drawPile.addAll(discardPile);
        discardPile
          ..clear()
          ..add(top);
        drawPile.shuffle(_random);
      }
      if (drawPile.isNotEmpty) hands[player].add(drawPile.removeLast());
    }
  }
}
