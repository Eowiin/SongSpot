import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/models/track.dart';

void main() {
  const album = Track(
    id: 'original-album',
    title: 'Blinding Lights',
    artist: 'The Weeknd',
    coverUrl: 'https://example.com/original.jpg',
    releaseYear: 2020,
  );

  test('best-of release is accepted despite another ID, cover and year', () {
    const bestOf = Track(
      id: 'best-of',
      title: 'Blinding Lights',
      artist: 'The Weeknd',
      coverUrl: 'https://example.com/best-of.jpg',
      releaseYear: 2025,
    );
    expect(album.matchesLegacyAnswer(bestOf), isTrue);
    expect(bestOf.matchesLegacyAnswer(album), isTrue);
  });

  test('case and whitespace differences do not reject the same song', () {
    expect(
      album.matchesLegacyAnswer(
        const Track(
          id: 'single',
          title: '  BLINDING   LIGHTS ',
          artist: 'the weeknd',
        ),
      ),
      isTrue,
    );
  });

  test('a cover by another artist is rejected', () {
    expect(
      album.matchesLegacyAnswer(
        const Track(
          id: 'cover',
          title: 'Blinding Lights',
          artist: 'Victoria Voss',
        ),
      ),
      isFalse,
    );
  });

  test('a different song by the same artist is rejected', () {
    expect(
      album.matchesLegacyAnswer(
        const Track(
          id: 'other',
          title: 'Save Your Tears',
          artist: 'The Weeknd',
        ),
      ),
      isFalse,
    );
  });

  test('missing answer metadata cannot match another release', () {
    const hidden = Track(id: 'hidden', title: '', artist: '');
    expect(hidden.matchesLegacyAnswer(album), isFalse);
    expect(
      hidden.matchesLegacyAnswer(
        const Track(id: 'other-hidden', title: '', artist: ''),
      ),
      isFalse,
    );
  });

  test('missing artist cannot establish song identity', () {
    const unknown = Track(id: 'unknown', title: 'Blinding Lights', artist: '');
    expect(
      unknown.matchesLegacyAnswer(
        const Track(id: 'other-unknown', title: 'Blinding Lights', artist: ''),
      ),
      isFalse,
    );
  });

  test('the same nonempty track ID remains accepted', () {
    expect(album.matchesLegacyAnswer(album), isTrue);
    const empty = Track(id: '', title: '', artist: '');
    expect(empty.matchesLegacyAnswer(empty), isFalse);
  });
}
