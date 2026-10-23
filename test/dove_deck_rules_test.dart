import 'package:flutter_test/flutter_test.dart';
import 'package:bestie/models/dove_deck_rules.dart';

void main() {
  group('DoveDeckRules', () {
    test('deals seven cards to each player and starts with a number card', () {
      final game = DoveDeckRules()..start();
      expect(game.hands[0], hasLength(7));
      expect(game.hands[1], hasLength(7));
      expect(game.topCard.kind, DoveCardKind.number);
      expect(game.finished, isFalse);
    });

    test('rejects a card that is not in the current hand', () {
      final game = DoveDeckRules()..start();
      expect(() => game.play('not-in-hand'), throwsStateError);
    });

    test('drawing locks playing until the player passes', () {
      final game = DoveDeckRules()..start();
      final player = game.currentPlayer;
      final before = game.hands[player].length;
      game.draw();
      expect(game.hands[player], hasLength(before + 1));
      expect(game.mustPassAfterDraw, isTrue);
      expect(() => game.draw(), throwsStateError);
      expect(() => game.play(game.hands[player].first.id), throwsStateError);
      game.pass();
      expect(game.currentPlayer, 1 - player);
    });

    test('wild cards require a chosen color', () {
      final game = DoveDeckRules()..start();
      final wild = DoveCard(id: 'test-wild', kind: DoveCardKind.wild);
      game.hands[game.currentPlayer].add(wild);
      expect(() => game.play(wild.id), throwsArgumentError);
    });

    test('serializes a card without losing its properties', () {
      const card = DoveCard(id: 'abc', kind: DoveCardKind.number, suit: DoveSuit.ocean, number: 7);
      final restored = DoveCard.fromJson(card.toJson());
      expect(restored.id, card.id);
      expect(restored.suit, card.suit);
      expect(restored.number, card.number);
    });
  });
}
