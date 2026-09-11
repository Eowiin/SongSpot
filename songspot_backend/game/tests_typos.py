"""
Typo tolerance for the guess box, on real queries.

Each query came back empty on prod in September 2026; each result is what
Deezer returned for it.
"""

from django.test import SimpleTestCase

from game.services import typos


class ResemblesTests(SimpleTestCase):
    def assertResembles(self, query, title, artist):
        self.assertTrue(typos.resembles(query, title, artist), (query, title, artist))

    def assertDoesNotResemble(self, query, title, artist):
        self.assertFalse(typos.resembles(query, title, artist), (query, title, artist))

    def test_a_letter_missing_or_wrong(self):
        self.assertResembles('bad buny', 'DtMF', 'Bad Bunny')
        self.assertResembles('shawn mendez', 'Treat You Better', 'Shawn Mendes')
        self.assertResembles('tyler the creater', 'See You Again', 'Tyler, The Creator')

    def test_two_letters_swapped(self):
        self.assertResembles('nigth trueno', 'NIGHT', 'Trueno')
        self.assertResembles('jucie wrld', 'Lucid Dreams', 'Juice Wrld')

    def test_words_typed_without_spaces(self):
        self.assertResembles('straykids', 'RUN IT', 'Stray Kids')
        self.assertResembles('karolg', 'TQG', 'KAROL G')

    def test_a_title_spelled_out_letter_by_letter(self):
        self.assertResembles('intro omar courtz', 'I N T R O', 'Omar Courtz')

    def test_a_short_word_the_title_does_not_have(self):
        self.assertResembles('la cancion con yandel', 'CANCIÓN CON YANDEL', 'Yandel')

    def test_the_last_word_may_be_unfinished(self):
        self.assertResembles('oliva rodr', 'drivers license', 'Olivia Rodrigo')

    def test_unrelated_results_are_rejected(self):
        self.assertDoesNotResemble('gina and georgia', "Gina And Elvira's Theme", 'Giorgio Moroder')
        self.assertDoesNotResemble('teueno', "T'es en love", 'La Famax')

    def test_a_three_letter_word_must_be_exact(self):
        self.assertDoesNotResemble('bad buu', 'NUEVAYoL', 'Bad Bunny')

    def test_every_longer_word_has_to_match(self):
        self.assertDoesNotResemble('tan bionica el regreso', 'Mil Días', 'Tan Bionica')
