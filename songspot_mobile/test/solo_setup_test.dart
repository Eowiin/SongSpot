import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/models/category.dart';
import 'package:songspot_mobile/models/solo_setup.dart';
import 'package:songspot_mobile/providers/game_session_provider.dart';

void main() {
  const pop = Category(
    id: 'p1',
    name: 'Pop',
    description: '',
    category: 'pop',
    trackCount: 579,
  );

  test('the first run is every genre at medium', () {
    expect(SoloSetup.initial.isMix, isTrue);
    expect(SoloSetup.initial.difficulty, Difficulty.medium);
  });

  test('a category and a difficulty are remembered', () {
    final saved = SoloSetup.initial.withCategory(pop).withDifficulty(Difficulty.hard);
    final restored = SoloSetup.fromJson(saved.toJson());
    expect(restored.isMix, isFalse);
    expect(restored.category, pop);
    expect(restored.difficulty, Difficulty.hard);
  });

  test('an artist is remembered with its Deezer id', () {
    final restored = SoloSetup.fromJson(
      SoloSetup.initial.withArtist('Damso', 4050205).toJson(),
    );
    expect(restored.artistName, 'Damso');
    expect(restored.artistDeezerId, 4050205);
    expect(restored.category, isNull);
  });

  test('choosing one source clears the other', () {
    final setup = SoloSetup.initial.withArtist('Damso', 1).withCategory(pop);
    expect(setup.artistName, isNull);
    expect(setup.withMix().isMix, isTrue);
  });

  test('an unreadable difficulty falls back to medium', () {
    expect(SoloSetup.fromJson({'difficulty': 'insane'}).difficulty, Difficulty.medium);
  });
}
