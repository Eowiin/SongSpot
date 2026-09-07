"""
Tests for song identity — the rule that decides whether a guess is right.

Cases are taken from real Deezer responses rather than invented, because the
whole point of this module is that the catalogue is messier than it looks.
"""

from django.test import SimpleTestCase

from game.services.matching import (
    answer_matches,
    is_junk_artist,
    is_variant_title,
    normalize_artist,
    normalize_title,
    song_key,
)


class NormalizeTitleTests(SimpleTestCase):
    def test_every_release_of_one_song_collapses_to_one_key(self):
        # These six are what `/search?q=blinding lights` and the artist's own
        # discography actually return. Under the old UUID rule, five of them
        # would be marked wrong.
        releases = [
            'Blinding Lights',
            'Blinding Lights (Remix)',
            'Blinding Lights (Live)',
            'Blinding Lights (Major Lazer Remix)',
            'Blinding Lights (Original Mix)',
            'Blinding Lights (Acoustic Version)',
            'Blinding Lights - Live',
            'Blinding Lights - 2020 Remaster',
        ]
        keys = {normalize_title(title) for title in releases}
        self.assertEqual(keys, {'blinding lights'})

    def test_featured_guests_are_dropped(self):
        self.assertEqual(
            normalize_title('Save Your Tears (feat. Ariana Grande)'),
            normalize_title('Save Your Tears'),
        )
        self.assertEqual(
            normalize_title('Get Lucky (feat. Pharrell Williams and Nile Rodgers)'),
            'get lucky',
        )

    def test_accents_and_punctuation_do_not_matter(self):
        self.assertEqual(normalize_title('Déjà Vu'), normalize_title('Deja Vu'))
        self.assertEqual(normalize_title("Ain't It Fun"), 'ain t it fun')

    def test_a_title_that_is_only_a_qualifier_keeps_a_key(self):
        # Stripping would empty this one out, and an empty key would match
        # every other emptied title.
        self.assertEqual(normalize_title('(Reprise)'), 'reprise')

    def test_leading_parenthetical_is_dropped(self):
        self.assertEqual(normalize_title("(I Can't Get No) Satisfaction"), 'satisfaction')

    def test_empty_input(self):
        self.assertEqual(normalize_title(''), '')
        self.assertEqual(normalize_title(None), '')


class NormalizeArtistTests(SimpleTestCase):
    def test_leading_the_is_ignored(self):
        self.assertEqual(normalize_artist('The Weeknd'), normalize_artist('Weeknd'))

    def test_collaborations_are_not_split(self):
        # Splitting on "&" or "," would turn these into different acts.
        self.assertEqual(normalize_artist('Simon & Garfunkel'), 'simon and garfunkel')
        self.assertEqual(normalize_artist('Tyler, The Creator'), 'tyler the creator')

    def test_featured_guests_are_dropped(self):
        self.assertEqual(normalize_artist('Drake feat. Future'), 'drake')

    def test_accents(self):
        self.assertEqual(normalize_artist('Beyoncé'), 'beyonce')


class VariantAndJunkTests(SimpleTestCase):
    def test_variants_are_recognised(self):
        for title in [
            'Blinding Lights (Live)',
            'Bohemian Rhapsody - 2011 Remaster',
            'Heroes - Live, December 1978',
            'Finally (Axwell Remix)',
        ]:
            self.assertTrue(is_variant_title(title), title)

    def test_plain_titles_and_features_are_not_variants(self):
        # A featured guest describes the song, not an alternate release.
        for title in ['Blinding Lights', 'Save Your Tears (feat. Ariana Grande)']:
            self.assertFalse(is_variant_title(title), title)

    def test_junk_artists(self):
        self.assertTrue(is_junk_artist('Karaoke Kings'))
        self.assertTrue(is_junk_artist('The Beatles Tribute Band'))
        self.assertFalse(is_junk_artist('The Weeknd'))


class AnswerMatchesTests(SimpleTestCase):
    ANSWER = dict(
        answer_deezer_id=908604612,
        answer_norm_title='blinding lights',
        answer_norm_artist='weeknd',
        answer_artist_deezer_id=4050205,
    )

    def test_same_song_other_release_is_correct(self):
        # The remix: different Deezer track, same song.
        self.assertTrue(answer_matches(
            **self.ANSWER,
            guess_deezer_id=1161752782,
            guess_norm_title='blinding lights',
            guess_norm_artist='weeknd',
            guess_artist_deezer_id=4050205,
        ))

    def test_identical_track_is_correct(self):
        self.assertTrue(answer_matches(
            **self.ANSWER,
            guess_deezer_id=908604612,
            guess_norm_title='blinding lights',
            guess_norm_artist='weeknd',
            guess_artist_deezer_id=4050205,
        ))

    def test_artist_entity_carries_a_differently_spelled_credit(self):
        self.assertTrue(answer_matches(
            **self.ANSWER,
            guess_deezer_id=999,
            guess_norm_title='blinding lights',
            guess_norm_artist='weeknd and someone else',
            guess_artist_deezer_id=4050205,
        ))

    def test_different_song_by_same_artist_is_wrong(self):
        self.assertFalse(answer_matches(
            **self.ANSWER,
            guess_deezer_id=111,
            guess_norm_title='save your tears',
            guess_norm_artist='weeknd',
            guess_artist_deezer_id=4050205,
        ))

    def test_same_title_by_an_unrelated_artist_is_wrong(self):
        self.assertFalse(answer_matches(
            **self.ANSWER,
            guess_deezer_id=222,
            guess_norm_title='blinding lights',
            guess_norm_artist='some other band',
            guess_artist_deezer_id=777,
        ))

    def test_empty_guess_is_wrong(self):
        self.assertFalse(answer_matches(
            **self.ANSWER,
            guess_deezer_id=None,
            guess_norm_title='',
            guess_norm_artist='',
            guess_artist_deezer_id=None,
        ))


class SongKeyTests(SimpleTestCase):
    def test_the_18_duplicate_groups_already_in_the_catalogue(self):
        # These pairs are real rows from the seeded catalogue. Before this
        # change they were distinct answers, so a player naming the song had
        # to also name the right release.
        self.assertEqual(
            song_key('Finally', 'Swedish House Mafia'),
            song_key('Finally (Axwell Remix)', 'Swedish House Mafia'),
        )
        self.assertEqual(
            song_key('Heroes - Live, September 1990', 'David Bowie'),
            song_key('Heroes - Live, December 1978', 'David Bowie'),
        )
