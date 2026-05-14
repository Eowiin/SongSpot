import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/providers/game_session_provider.dart';

void main() {
  group('Difficulty', () {
    test('easy has 15s snippet duration', () {
      expect(Difficulty.easy.snippetDuration, const Duration(seconds: 15));
    });

    test('medium has 5s snippet duration', () {
      expect(Difficulty.medium.snippetDuration, const Duration(seconds: 5));
    });

    test('hard has 1s snippet duration', () {
      expect(Difficulty.hard.snippetDuration, const Duration(seconds: 1));
    });

    test('easy has 1.0x score multiplier', () {
      expect(Difficulty.easy.scoreMultiplier, 1.0);
    });

    test('medium has 1.5x score multiplier', () {
      expect(Difficulty.medium.scoreMultiplier, 1.5);
    });

    test('hard has 2.0x score multiplier', () {
      expect(Difficulty.hard.scoreMultiplier, 2.0);
    });

    test('name returns lowercase string', () {
      expect(Difficulty.easy.name, 'easy');
      expect(Difficulty.medium.name, 'medium');
      expect(Difficulty.hard.name, 'hard');
    });

    test('label returns human-readable string', () {
      expect(Difficulty.easy.label, 'Easy');
      expect(Difficulty.medium.label, 'Medium');
      expect(Difficulty.hard.label, 'Hard');
    });
  });

  group('SessionEndReason', () {
    test('values exist', () {
      expect(SessionEndReason.values, contains(SessionEndReason.outOfLives));
      expect(SessionEndReason.values, contains(SessionEndReason.poolCleared));
      expect(SessionEndReason.values, contains(SessionEndReason.quit));
    });
  });

  group('GuessResult', () {
    test('values exist', () {
      expect(GuessResult.values, contains(GuessResult.correct));
      expect(GuessResult.values, contains(GuessResult.wrong));
      expect(GuessResult.values, contains(GuessResult.none));
    });
  });
}
