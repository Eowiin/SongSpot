"""
Tests for the parts that changed when previews stopped being storable.

Deezer is mocked throughout. What is asserted here is our own economics — that
one container call serves many players, that a round never plays silence, and
that the search box never waits on the network — not Deezer's behaviour.
"""

from unittest.mock import patch

from django.test import override_settings
from django.urls import reverse

from game.models import Artist, CatalogSetting, Playlist, PlaylistTrack, SearchMiss, Track
from game.services import catalog, previews
from game.services.deezer_http import DeezerUnavailable

from .tests_open_catalog import CatalogTestCase, make_track


def signed(track_id, url=None):
    """A payload row shaped like Deezer's, with a preview."""
    return {'id': track_id, 'preview': url or f'https://cdnt.example/{track_id}.mp3'}


class ContainerPoolTests(CatalogTestCase):
    """
    One call, many players.

    This is the property the whole design rests on: a preview token is bound to
    neither a player nor an IP, so every player on a container can share one
    response for the length of the cache window. If this stops holding, the
    call volume goes from "per container per ten minutes" back to "per round",
    which is a sixty-fold increase.
    """

    @patch('game.services.previews._http')
    def test_a_second_caller_pays_nothing(self, mock_http):
        mock_http.return_value.get.return_value = {'data': [signed(1), signed(2)]}

        first = previews.container_previews('artist', 27)
        second = previews.container_previews('artist', 27)

        self.assertEqual(len(first), 2)
        self.assertEqual(first, second)
        self.assertEqual(mock_http.return_value.get.call_count, 1)

    @patch('game.services.previews._http')
    def test_rows_without_audio_are_dropped(self, mock_http):
        mock_http.return_value.get.return_value = {
            'data': [signed(1), {'id': 2, 'preview': ''}, {'preview': 'x'}],
        }
        self.assertEqual(list(previews.container_previews('chart', 132)), [1])

    @patch('game.services.previews._http')
    def test_a_failure_is_not_cached(self, mock_http):
        """
        A refusal must be retried on the next round, not held for ten minutes.

        Caching the empty result would turn one transient Deezer refusal into
        ten minutes of silent rounds for every player on that container.
        """
        mock_http.return_value.get.side_effect = DeezerUnavailable('quota')

        self.assertEqual(previews.container_previews('artist', 27), {})
        self.assertEqual(previews.container_previews('artist', 27), {})
        self.assertEqual(mock_http.return_value.get.call_count, 2)


@override_settings(PREVIEWS_FAKE_URL=False)
class ResolveTests(CatalogTestCase):
    """
    These exercise the resolver itself, so they turn off the synthetic URL that
    lets every other test play a round without touching the network.
    """

    def setUp(self):
        super().setUp()
        self.track = make_track('Around the World', 'Daft Punk', deezer_id=3135556, artist_id=27)

    @patch('game.services.previews.single_preview')
    @patch('game.services.previews._http')
    def test_a_container_hit_costs_no_extra_call(self, mock_http, mock_single):
        mock_http.return_value.get.return_value = {'data': [signed(3135556, 'https://c/ok.mp3')]}

        url = previews.resolve(self.track, [('playlist', 999)])

        self.assertEqual(url, 'https://c/ok.mp3')
        mock_single.assert_not_called()

    @patch('game.services.previews.single_preview')
    @patch('game.services.previews._http')
    def test_it_falls_through_container_then_artist_then_track(self, mock_http, mock_single):
        # Neither the playlist nor the artist pool holds this track.
        mock_http.return_value.get.return_value = {'data': [signed(111)]}
        mock_single.return_value = 'https://c/single.mp3'

        url = previews.resolve(self.track, [('playlist', 999)])

        self.assertEqual(url, 'https://c/single.mp3')
        mock_single.assert_called_once_with(3135556)

    def test_a_track_with_no_deezer_id_resolves_to_nothing(self):
        """
        The Deezer track ID is the only handle the resolver has.

        Rows seeded before IDs were recorded therefore have no way to produce
        audio, which is why `playable()` now excludes them outright rather than
        letting them reach a round and fail there.
        """
        legacy = Track.objects.create(title='Seeded', artist='Old', has_preview=True)
        self.assertIsNone(previews.resolve(legacy))


class RoundAudioTests(CatalogTestCase):
    """`/next-song/` must never hand a client a round it cannot play."""

    def setUp(self):
        super().setUp()
        self.unresolvable = make_track('No Audio', 'Ghost', deezer_id=901, rank=900_000)
        self.playable = make_track('Real Song', 'Ghost', deezer_id=902, rank=900_000)

    @patch('game.views.previews.resolve')
    def test_a_track_whose_audio_will_not_resolve_is_skipped(self, mock_resolve):
        # The first candidate tried resolves to nothing; a later one works.
        mock_resolve.side_effect = lambda track, containers=(): (
            'https://c/fresh.mp3' if track.deezer_id == 902 else None
        )

        response = self.client.get(reverse('game:next_song'), {'v': 2})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['preview_url'], 'https://c/fresh.mp3')

    @patch('game.views.previews.resolve', return_value='https://c/fresh.mp3')
    def test_the_resolved_url_has_nowhere_to_be_written_back_to(self, _resolve):
        """
        A fifteen-minute URL in a table read days later was the original bug.
        The column is gone, so the mistake is now unmakeable.
        """
        response = self.client.get(reverse('game:next_song'), {'v': 2})

        self.assertEqual(response.data['preview_url'], 'https://c/fresh.mp3')
        self.assertFalse(hasattr(Track.objects.get(pk=self.playable.pk), 'preview_url'))

    @patch('game.views.previews.resolve', return_value=None)
    def test_an_outage_is_reported_as_unavailable_not_as_an_empty_catalogue(
        self, _resolve,
    ):
        """
        503, not 404.

        The two mean different things to a player: "we have no songs for you"
        sends them to the uninstall button, "try again in a moment" does not.
        """
        response = self.client.get(reverse('game:next_song'), {'v': 2})
        self.assertEqual(response.status_code, 503)


class CategoryContainerTests(CatalogTestCase):
    def test_a_category_passes_its_deezer_containers_to_the_resolver(self):
        playlist = Playlist.objects.create(
            name='Pop', category='pop', deezer_genre_id=132,
            deezer_playlist_ids=[555],
        )
        track = make_track('Hit', 'Star', deezer_id=42, rank=900_000)
        PlaylistTrack.objects.create(playlist=playlist, track=track)

        with patch('game.views.previews.resolve', return_value='https://c/x.mp3') as resolve:
            self.client.get(reverse('game:next_song'), {'playlist': str(playlist.id), 'v': 2})

        containers = resolve.call_args[0][1]
        # Editorial playlists first, then the genre chart.
        self.assertEqual(containers, [('playlist', 555), ('chart', 132)])


class BulkUpsertTests(CatalogTestCase):
    """
    The batch path has to reproduce `upsert_track` exactly, because it replaced
    it on every import path. `bulk_create` bypasses `Model.save()`, so anything
    that save() maintained has to be maintained here by hand — and a missing
    `norm_title` is not a visible bug, it is a guess that silently stops
    matching.
    """

    def info(self, title, artist, deezer_id, **kw):
        return {
            'title': title, 'artist': artist, 'deezer_id': deezer_id,
            'preview_url': f'https://e/{deezer_id}.mp3',
            'deezer_artist_id': kw.pop('artist_id', 27), **kw,
        }

    def test_identity_columns_are_computed(self):
        catalog.bulk_upsert_tracks([self.info('ROSALÍA Song', 'ROSALÍA', 1)])
        track = Track.objects.get(deezer_id=1)
        self.assertEqual(track.norm_title, 'rosalia song')
        self.assertEqual(track.norm_artist, 'rosalia')

    def test_variants_are_flagged_on_the_way_in(self):
        catalog.bulk_upsert_tracks([
            self.info('Blinding Lights', 'The Weeknd', 1),
            self.info('Blinding Lights (Live)', 'The Weeknd', 2),
        ])
        self.assertFalse(Track.objects.get(deezer_id=1).is_variant)
        self.assertTrue(Track.objects.get(deezer_id=2).is_variant)

    def test_an_id_less_legacy_row_is_adopted_not_duplicated(self):
        Track.objects.create(
            title='Seeded Song', artist='Seeded Act', has_preview=True,
        )
        catalog.bulk_upsert_tracks([self.info('Seeded Song', 'Seeded Act', 77)])

        self.assertEqual(Track.objects.filter(norm_title='seeded song').count(), 1)
        self.assertEqual(Track.objects.get(norm_title='seeded song').deezer_id, 77)

    def test_a_second_release_of_the_same_song_stays_separate(self):
        make_track('Blinding Lights', 'The Weeknd', deezer_id=1)
        catalog.bulk_upsert_tracks([self.info('Blinding Lights', 'The Weeknd', 2)])
        self.assertEqual(Track.objects.filter(norm_title='blinding lights').count(), 2)

    def test_metadata_only_fills_gaps_and_never_churns(self):
        make_track('Song', 'Act', deezer_id=5, rank=100)
        catalog.bulk_upsert_tracks([
            self.info('Song', 'Act', 5, rank=999, genre='Pop'),
        ])
        track = Track.objects.get(deezer_id=5)
        self.assertEqual(track.genre, 'Pop')      # was empty, filled
        self.assertEqual(track.rank, 100)         # already set, untouched

    def test_a_row_without_audio_gains_the_flag(self):
        make_track('Song', 'Act', deezer_id=6).__class__.objects.filter(
            deezer_id=6,
        ).update(has_preview=False)
        catalog.bulk_upsert_tracks([self.info('Song', 'Act', 6)])
        self.assertTrue(Track.objects.get(deezer_id=6).has_preview)

    def test_payloads_without_audio_are_rejected(self):
        catalog.bulk_upsert_tracks([
            {'title': 'X', 'artist': 'Y', 'deezer_id': 9, 'preview_url': ''},
        ])
        self.assertFalse(Track.objects.filter(deezer_id=9).exists())


class VariantPlayabilityTests(CatalogTestCase):
    """
    Variants are answers, not rounds.

    The gap this closes: the import-time variant check is skipped for directed
    picks, so an artist session legitimately pulls "(Live)" cuts into the
    table. Before `is_variant` existed, `playable()` had no way to tell them
    apart afterwards and a category round could land on one.
    """

    def setUp(self):
        super().setUp()
        self.studio = make_track('Blinding Lights', 'The Weeknd', deezer_id=1, rank=900_000)
        self.live = make_track('Blinding Lights (Live)', 'The Weeknd', deezer_id=2, rank=900_000)

    def test_an_undirected_pick_never_lands_on_a_variant(self):
        playable = catalog.playable(Track.objects.all(), directed=False)
        self.assertNotIn(self.live, playable)
        self.assertIn(self.studio, playable)

    def test_a_directed_pick_still_gets_the_whole_discography(self):
        playable = catalog.playable(Track.objects.all(), directed=True)
        self.assertIn(self.live, playable)

    def test_a_variant_is_still_a_correct_answer(self):
        self.assertTrue(catalog.check_guess(self.studio, guess_track_id=str(self.live.id)))


class EnrichmentTests(CatalogTestCase):
    """
    The search box answers from Postgres. Deezer is called after the response,
    once per query per week — not once per keystroke.
    """

    @patch('game.services.catalog.DeezerService')
    def test_a_query_with_local_results_makes_no_live_call(self, mock_deezer):
        for i in range(catalog.ENRICH_BELOW + 1):
            make_track(f'Blinding Lights {i}', f'Act {i}', deezer_id=100 + i)

        catalog.search_tracks('blinding')

        mock_deezer.return_value.search_track.assert_not_called()

    @patch('game.services.catalog.DeezerService')
    def test_an_empty_query_is_enriched_once_and_then_never_again(self, mock_deezer):
        mock_deezer.return_value.search_track.return_value = {'data': []}

        catalog.search_tracks('nothing here')
        catalog.search_tracks('nothing here')
        catalog.search_tracks('NOTHING  HERE')  # same query once normalised

        self.assertEqual(mock_deezer.return_value.search_track.call_count, 1)

    @patch('game.services.catalog.DeezerService')
    def test_an_empty_query_is_recorded_for_the_crawler(self, mock_deezer):
        mock_deezer.return_value.search_track.return_value = {'data': []}

        catalog.search_tracks('obscure band')
        catalog.search_tracks('obscure band')

        miss = SearchMiss.objects.get(norm_query='obscure band')
        self.assertEqual(miss.hits, 2)

    @patch('game.services.catalog.DeezerService')
    def test_artist_results_deezer_found_are_used_even_if_we_cannot_re_find_them(
        self, mock_deezer,
    ):
        """
        Deezer's matching is fuzzier than ours: `band` returns "Karaoke Kings",
        which no `icontains` of ours will ever match. Re-reading the table
        after enrichment would silently drop those results.
        """
        mock_deezer.return_value.search_artists.return_value = [
            {'id': 1, 'name': 'Karaoke Kings', 'nb_fan': 9_000_000},
            {'id': 2, 'name': 'Real Band', 'nb_fan': 1_000},
        ]
        names = [a.name for a in catalog.search_artists('band')]
        self.assertIn('Karaoke Kings', names)
        self.assertEqual(names[0], 'Real Band')


class LegacyArtistTests(CatalogTestCase):
    """
    Artists we only know by name must not look like coverage.

    The seeded catalogue holds acts with a name and no `deezer_artist_id`.
    `_local_artists` returns stand-ins for them so they stay searchable, and
    those stand-ins once counted towards the "do we know this query?" test —
    which meant a search that returned only stand-ins never triggered
    enrichment, and the act could never be promoted to a real Deezer entity.
    """

    def setUp(self):
        super().setUp()
        Track.objects.create(
            title='Old Song', artist='Legacy Act', has_preview=True,
        )

    @patch('game.services.catalog.DeezerService')
    def test_a_name_only_match_still_triggers_enrichment(self, mock_deezer):
        mock_deezer.return_value.search_artists.return_value = [
            {'id': 555, 'name': 'Legacy Act', 'nb_fan': 120_000},
        ]

        results = catalog.search_artists('Legacy Act')

        mock_deezer.return_value.search_artists.assert_called_once()
        self.assertEqual(results[0].deezer_id, 555)

    @patch('game.services.catalog.DeezerService')
    def test_an_act_deezer_does_not_know_keeps_its_stand_in(self, mock_deezer):
        mock_deezer.return_value.search_artists.return_value = []

        results = catalog.search_artists('Legacy Act')

        self.assertEqual([a.name for a in results], ['Legacy Act'])
        self.assertIsNone(results[0].deezer_id)

    @patch('game.services.catalog.DeezerService')
    def test_resolve_artist_refuses_a_near_miss(self, mock_deezer):
        """A fuzzy match must never be stamped onto a whole discography."""
        mock_deezer.return_value.search_artists.return_value = [
            {'id': 1, 'name': 'The Retro Weeknd', 'nb_fan': 64},
        ]
        self.assertIsNone(catalog.resolve_artist('The Weeknd'))

    @patch('game.services.catalog.DeezerService')
    def test_resolve_artist_breaks_ties_on_followers(self, mock_deezer):
        mock_deezer.return_value.search_artists.return_value = [
            {'id': 1, 'name': 'Nova', 'nb_fan': 500},
            {'id': 2, 'name': 'Nova', 'nb_fan': 900_000},
        ]
        self.assertEqual(catalog.resolve_artist('Nova').deezer_id, 2)
