import 'dart:math';

enum DoveSuit { coral, ocean, leaf, sun }
enum DoveCardKind { number, skip, reverse, drawTwo, wild, wildDrawFour }

class DoveCard {
  const DoveCard({required this.id, required this.kind, this.suit, this.number});
  final String id;
  final DoveSuit? suit;
  final DoveCardKind kind;
  final int? number;

  bool get isWild => suit == null;
  String get label => switch (kind) {
    DoveCardKind.number => '${number ?? 0}',
    DoveCardKind.skip => 'ATLA',
    DoveCardKind.reverse => 'TERS',
    DoveCardKind.drawTwo => '+2',
    DoveCardKind.wild => 'JOKER',
    DoveCardKind.wildDrawFour => '+4',
  };

  Map<String, dynamic> toJson() => {
    'id': id, 'kind': kind.name, 'suit': suit?.name, 'number': number,
  };

  factory DoveCard.fromJson(Map<String, dynamic> json) => DoveCard(
    id: json['id'] as String,
    kind: DoveCardKind.values.byName(json['kind'] as String),
    suit: json['suit'] == null ? null : DoveSuit.values.byName(json['suit'] as String),
    number: (json['number'] as num?)?.toInt(),
  );
}

/// Rules for a two-player partner match. This class is a deterministic rules
/// engine for UI previews/tests; production moves must be validated server-side.
class DoveDeckRules {
  DoveDeckRules({Random? random}) : _random = random ?? Random();
  final Random _random;
  late List<List<DoveCard>> hands;
  late List<DoveCard> drawPile;
  late List<DoveCard> discardPile;
  int currentPlayer = 0;
  DoveSuit? chosenSuit;
  bool finished = false;
  int? winner;
  bool mustPassAfterDraw = false;

  DoveCard get topCard => discardPile.last;
  List<DoveCard> get currentHand => hands[currentPlayer];

  void start() {
    hands = [<DoveCard>[], <DoveCard>[]];
    drawPile = _makeDeck()..shuffle(_random);
    discardPile = <DoveCard>[];
    currentPlayer = 0;
    chosenSuit = null;
    finished = false;
    winner = null;
    mustPassAfterDraw = false;
    for (var i = 0; i < 7; i++) {
      hands[0].add(drawPile.removeLast());
      hands[1].add(drawPile.removeLast());
    }
    while (drawPile.isNotEmpty) {
      final first = drawPile.removeLast();
      if (first.kind == DoveCardKind.number) {
        discardPile.add(first);
        break;
      }
      drawPile.insert(0, first);
    }
  }

  static List<DoveCard> _makeDeck() {
    final cards = <DoveCard>[];
    var id = 0;
    for (final suit in DoveSuit.values) {
      for (var number = 0; number <= 9; number++) {
        cards.add(DoveCard(id: 'c${id++}', suit: suit, kind: DoveCardKind.number, number: number));
        if (number != 0) {
          cards.add(DoveCard(id: 'c${id++}', suit: suit, kind: DoveCardKind.number, number: number));
        }
      }
      for (final kind in [DoveCardKind.skip, DoveCardKind.reverse, DoveCardKind.drawTwo]) {
        for (var copy = 0; copy < 2; copy++) {
          cards.add(DoveCard(id: 'c${id++}', suit: suit, kind: kind));
        }
      }
    }
    for (var i = 0; i < 4; i++) {
      cards.add(DoveCard(id: 'c${id++}', kind: DoveCardKind.wild));
      cards.add(DoveCard(id: 'c${id++}', kind: DoveCardKind.wildDrawFour));
    }
    return cards;
  }

  bool canPlay(DoveCard card) {
    if (finished || mustPassAfterDraw || !currentHand.any((c) => c.id == card.id)) return false;
    if (card.isWild) return true;
    final activeSuit = chosenSuit ?? topCard.suit;
    return card.suit == activeSuit ||
        (card.kind == DoveCardKind.number &&
         topCard.kind == DoveCardKind.number &&
         card.number == topCard.number);
  }

  void play(String cardId, {DoveSuit? wildSuit}) {
    if (finished) throw StateError('Oyun tamamlandı.');
    final card = currentHand.where((c) => c.id == cardId).firstOrNull;
    if (card == null || !canPlay(card)) throw StateError('Bu kart oynanamaz.');
    if (card.isWild && wildSuit == null) throw ArgumentError('Joker için renk seçmelisin.');
    currentHand.removeWhere((c) => c.id == cardId);
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
        currentPlayer = 1 - currentPlayer; // In a two-player game these skip the opponent.
        break;
      case DoveCardKind.drawTwo:
        _drawTo(1 - currentPlayer, 2);
        currentPlayer = 1 - currentPlayer;
        break;
      case DoveCardKind.wildDrawFour:
        _drawTo(1 - currentPlayer, 4);
        currentPlayer = 1 - currentPlayer;
        break;
      case DoveCardKind.number:
      case DoveCardKind.wild:
        currentPlayer = 1 - currentPlayer;
        break;
    }
  }

  void draw() {
    if (finished || mustPassAfterDraw) throw StateError('Şu anda kart çekemezsin.');
    _drawTo(currentPlayer, 1);
    mustPassAfterDraw = true;
  }

  void pass() {
    if (!mustPassAfterDraw || finished) throw StateError('Önce kart çekmelisin.');
    mustPassAfterDraw = false;
    currentPlayer = 1 - currentPlayer;
  }

  void _drawTo(int player, int count) {
    for (var i = 0; i < count; i++) {
      if (drawPile.isEmpty) {
        if (discardPile.length <= 1) return;
        final top = discardPile.removeLast();
        drawPile = discardPile..shuffle(_random);
        discardPile = [top];
      }
      if (drawPile.isNotEmpty) hands[player].add(drawPile.removeLast());
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
