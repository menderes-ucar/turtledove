
import 'dart:math';

enum DoveSuit { coral, ocean, leaf, sun }

enum DoveCardKind { number, skip, reverse, drawTwo, wild, wildDrawFour }

class DoveCard {
  const DoveCard({
    required this.id,
    required this.kind,
    this.suit,
    this.number,
  });

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
    'id': id,
    'kind': kind.name,
    'suit': suit?.name,
    'number': number,
  };

  factory DoveCard.fromJson(Map<String, dynamic> json) => DoveCard(
    id: json['id'] as String,
    kind: DoveCardKind.values.byName(json['kind'] as String),
    suit: json['suit'] == null
        ? null
        : DoveSuit.values.byName(json['suit'] as String),
    number: (json['number'] as num?)?.toInt(),
  );
}

/// Two-player Dove Deck rules engine.
///
/// pendingDraw must be included in the persisted game state so both devices
/// can reconstruct the same penalty-stack state.
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

  /// Number of penalty cards accumulated by +2 / +4 stacking.
  int pendingDraw = 0;

  /// Kind of penalty currently on the stack.
  DoveCardKind? pendingDrawKind;

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
    pendingDraw = 0;
    pendingDrawKind = null;

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
        cards.add(DoveCard(
          id: 'c${id++}',
          suit: suit,
          kind: DoveCardKind.number,
          number: number,
        ));

        if (number != 0) {
          cards.add(DoveCard(
            id: 'c${id++}',
            suit: suit,
            kind: DoveCardKind.number,
            number: number,
          ));
        }
      }

      for (final kind in [
        DoveCardKind.skip,
        DoveCardKind.reverse,
        DoveCardKind.drawTwo,
      ]) {
        for (var copy = 0; copy < 2; copy++) {
          cards.add(DoveCard(
            id: 'c${id++}',
            suit: suit,
            kind: kind,
          ));
        }
      }
    }

    for (var i = 0; i < 4; i++) {
      cards.add(DoveCard(id: 'c${id++}', kind: DoveCardKind.wild));
      cards.add(DoveCard(
        id: 'c${id++}',
        kind: DoveCardKind.wildDrawFour,
      ));
    }

    return cards;
  }

  bool canPlay(DoveCard card) {
    if (finished ||
        mustPassAfterDraw ||
        !currentHand.any((c) => c.id == card.id)) {
      return false;
    }

    if (pendingDraw > 0) {
      // A penalty can only be stacked with another penalty card of the
      // same kind. +2 stacks on +2; +4 stacks on +4.
      if (pendingDrawKind == DoveCardKind.drawTwo) {
        return card.kind == DoveCardKind.drawTwo;
      }

      if (pendingDrawKind == DoveCardKind.wildDrawFour) {
        return card.kind == DoveCardKind.wildDrawFour;
      }

      return false;
    }

    if (card.isWild) return true;

    final activeSuit = chosenSuit ?? topCard.suit;

    return card.suit == activeSuit ||
        (card.kind == DoveCardKind.number &&
            topCard.kind == DoveCardKind.number &&
            card.number == topCard.number);
  }

  void play(String cardId, {DoveSuit? wildSuit}) {
    if (finished) {
      throw StateError('Oyun tamamlandı.');
    }

    final card = currentHand.where((c) => c.id == cardId).firstOrNull;

    if (card == null || !canPlay(card)) {
      throw StateError('Bu kart oynanamaz.');
    }

    if (card.isWild && wildSuit == null) {
      throw ArgumentError('Joker için renk seçmelisin.');
    }

    currentHand.removeWhere((c) => c.id == cardId);
    discardPile.add(card);
    chosenSuit = card.isWild ? wildSuit : null;

    if (currentHand.isEmpty) {
      finished = true;
      winner = currentPlayer;
      pendingDraw = 0;
      pendingDrawKind = null;
      mustPassAfterDraw = false;
      return;
    }

    switch (card.kind) {
      case DoveCardKind.drawTwo:
        pendingDraw += 2;
        pendingDrawKind = DoveCardKind.drawTwo;
        currentPlayer = 1 - currentPlayer;
        break;

      case DoveCardKind.wildDrawFour:
        pendingDraw += 4;
        pendingDrawKind = DoveCardKind.wildDrawFour;
        currentPlayer = 1 - currentPlayer;
        break;

      case DoveCardKind.skip:
      case DoveCardKind.reverse:
      case DoveCardKind.number:
      case DoveCardKind.wild:
        currentPlayer = 1 - currentPlayer;
        break;
    }
  }

  /// Draws the accumulated penalty, or one normal card.
  ///
  /// When a penalty is pending, the player cannot draw only one card:
  /// they must take the entire accumulated penalty and lose their turn.
  void draw() {
    if (finished || mustPassAfterDraw) {
      throw StateError('Şu anda kart çekemezsin.');
    }

    if (pendingDraw > 0) {
      final count = pendingDraw;
      _drawTo(currentPlayer, count);
      pendingDraw = 0;
      pendingDrawKind = null;
      mustPassAfterDraw = false;
      currentPlayer = 1 - currentPlayer;
      return;
    }

    _drawTo(currentPlayer, 1);
    mustPassAfterDraw = true;
  }

  /// Ends a normal draw turn. Penalty draws automatically advance the turn
  /// inside draw(), so they do not need a separate pass action.
  void pass() {
    if (!mustPassAfterDraw || finished) {
      throw StateError('Önce normal bir kart çekmelisin.');
    }

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

      if (drawPile.isNotEmpty) {
        hands[player].add(drawPile.removeLast());
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'hands': hands
        .map((hand) => hand.map((card) => card.toJson()).toList())
        .toList(),
    'drawPile': drawPile.map((card) => card.toJson()).toList(),
    'discardPile': discardPile.map((card) => card.toJson()).toList(),
    'currentPlayer': currentPlayer,
    'chosenSuit': chosenSuit?.name,
    'finished': finished,
    'winner': winner,
    'mustPassAfterDraw': mustPassAfterDraw,
    'pendingDraw': pendingDraw,
    'pendingDrawKind': pendingDrawKind?.name,
  };

  factory DoveDeckRules.fromJson(
      Map<String, dynamic> json, {
        Random? random,
      }) {
    final rules = DoveDeckRules(random: random);

    List<DoveCard> decodeCards(dynamic value) =>
        (value as List? ?? const [])
            .map((item) => DoveCard.fromJson(
          Map<String, dynamic>.from(item as Map),
        ))
            .toList();

    final handsJson = json['hands'] as List? ?? const [];

    rules.hands = [
      decodeCards(handsJson.isNotEmpty ? handsJson[0] : null),
      decodeCards(handsJson.length > 1 ? handsJson[1] : null),
    ];

    rules.drawPile = decodeCards(json['drawPile']);
    rules.discardPile = decodeCards(json['discardPile']);
    rules.currentPlayer =
        (json['currentPlayer'] as num?)?.toInt() ?? 0;

    rules.chosenSuit = json['chosenSuit'] == null
        ? null
        : DoveSuit.values.byName(json['chosenSuit'] as String);

    rules.finished = json['finished'] == true;
    rules.winner = (json['winner'] as num?)?.toInt();
    rules.mustPassAfterDraw = json['mustPassAfterDraw'] == true;
    rules.pendingDraw = (json['pendingDraw'] as num?)?.toInt() ?? 0;

    rules.pendingDrawKind = json['pendingDrawKind'] == null
        ? (rules.pendingDraw > 0
        ? DoveCardKind.drawTwo
        : null)
        : DoveCardKind.values.byName(json['pendingDrawKind'] as String);

    return rules;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
