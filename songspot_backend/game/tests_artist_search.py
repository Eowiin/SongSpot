"""
Artist autocomplete ranking.

Two cases pull in opposite directions and both have to hold at once. Ranking on
audience alone answers the second and breaks the first; ranking on relevance
alone answers the first and breaks the second. Tiers with popularity as an
in-tier tiebreaker are what satisfy both, so both are pinned here.
"""

from unittest.mock import patch

from django.test import TestCase

from game.models import Artist
from game.services import catalog
from game.services.matching import normalize_artist


def _artist(deezer_id: int, name: str, nb_fan: int, **kwargs) -> Artist:
    # Through the real normaliser, so the rows carry what production would
    # store — 'The Weeknd' folding to 'weeknd' is load-bearing below.
    return Artist.objects.create(
        deezer_id=deezer_id, name=name, norm_name=normalize_artist(name),
        nb_fan=nb_fan, **kwargs
    )


class ArtistSearchRankingTests(TestCase):
    def _search(self, query, limit=30):
        # No Deezer: this is about ordering what is already held.
        with patch.object(catalog, '_enrich_now', return_value=[]), \
             patch.object(catalog, '_enrich_later', return_value=None):
            return [a.name for a in catalog.search_artists(query, limit=limit)]

    def test_an_exact_match_outranks_far_bigger_names_containing_it(self):
        # The reported bug: every one of these buried NeS on follower count.
        _artist(1, 'The Rolling Stones', 7_092_039)
        _artist(2, 'Evanescence', 3_779_694)
        _artist(3, 'Genesis', 1_189_701)
        _artist(4, 'NeS', 67_774)

        self.assertEqual(self._search('nes')[0], 'NeS')

    def test_popularity_still_decides_between_equally_exact_matches(self):
        # Why the audience sort was introduced: Deezer ranked the 2 101-fan
        # namesake above the real one. Tiers must not undo that.
        _artist(1, 'Weeknd', 2_101)
        _artist(2, 'The Weeknd', 14_659_544)

        self.assertEqual(self._search('weeknd')[0], 'The Weeknd')

    def test_a_prefix_beats_a_name_merely_containing_the_query(self):
        _artist(1, 'Evanescence', 3_779_694)
        _artist(2, 'Nesly', 40_000)

        self.assertEqual(self._search('nes')[0], 'Nesly')

    def test_case_and_accents_do_not_change_the_ranking(self):
        _artist(1, 'The Rolling Stones', 7_092_039)
        _artist(2, 'NeS', 67_774)

        for typed in ('nes', 'NES', 'NÈS', 'nEs'):
            self.assertEqual(self._search(typed)[0], 'NeS', f'failed for {typed!r}')

    def test_junk_acts_rank_last_even_on_an_exact_match(self):
        _artist(1, 'NeS', 67_774, is_junk=True)
        _artist(2, 'Nesly', 40_000)

        self.assertEqual(self._search('nes')[-1], 'NeS')

    def test_a_blocked_artist_never_appears(self):
        _artist(1, 'NeS', 67_774, is_blocked=True)
        _artist(2, 'Nesly', 40_000)

        self.assertNotIn('NeS', self._search('nes'))

    def test_a_collaboration_credit_never_appears(self):
        # Deezer's entity for a multi-artist credit: separator and no photo.
        empty = 'https://cdn-images.dzcdn.net/images/artist//1000x1000-000000-80-0-0.jpg'
        _artist(1, 'Damso', 5_119_127, picture_url='https://example.test/damso.jpg')
        _artist(2, 'No Limit, Gazo & Damso', 2_415, picture_url=empty)
        _artist(3, 'Zola feat. Damso, PRINC€', 2, picture_url=empty)

        self.assertEqual(self._search('damso'), ['Damso'])

    def test_real_acts_with_a_separator_or_no_photo_still_appear(self):
        empty = 'https://cdn-images.dzcdn.net/images/artist//1000x1000-000000-80-0-0.jpg'
        _artist(1, 'Simon & Garfunkel', 1_165_430, picture_url='https://example.test/sg.jpg')
        _artist(2, 'Simon Unknown', 12, picture_url=empty)

        self.assertEqual(self._search('simon'), ['Simon & Garfunkel', 'Simon Unknown'])

    def test_the_best_match_survives_a_crowded_field(self):
        # The slice defect: with no ordering before the cut, the one exact
        # match was dropped before anything ranked it.
        for i in range(200):
            _artist(1000 + i, f'Bones Crew {i}', 500_000 + i)
        _artist(1, 'NeS', 67_774)

        self.assertEqual(self._search('nes', limit=30)[0], 'NeS')
