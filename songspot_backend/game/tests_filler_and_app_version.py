"""
Album filler stays out of rounds, and the app learns which version it must run.
"""

from django.test import SimpleTestCase, TestCase
from django.urls import reverse

from game.models import AppRelease, Track
from game.services import catalog
from game.services.matching import is_non_song


class IsNonSongTests(SimpleTestCase):
    def test_voice_notes_and_narration_by_length(self) -> None:
        self.assertTrue(is_non_song('Voice Note (JAKE Ver.)', 36))
        self.assertTrue(is_non_song('The Final Moment', 78))

    def test_short_named_filler(self) -> None:
        self.assertTrue(is_non_song('Intro : Whiteout', 99))
        self.assertTrue(is_non_song('Interlude : Question', 84))

    def test_skit_whatever_its_length(self) -> None:
        self.assertTrue(is_non_song('Steve Berman (Skit)', None))
        self.assertTrue(is_non_song('Skit', 200))

    def test_real_songs_are_kept(self) -> None:
        self.assertFalse(is_non_song('Intro', 127))  # The xx
        self.assertFalse(is_non_song('Drunk-Dazed', 194))
        self.assertFalse(is_non_song('Introvert', 95))  # "intro" only as a word

    def test_unknown_length_is_not_judged(self) -> None:
        self.assertFalse(is_non_song('Voice Note (JAKE Ver.)', None))
        self.assertFalse(is_non_song('Breaking News', 0))


def _track(title: str, duration: int | None, deezer_id: int) -> Track:
    return Track.objects.create(
        title=title, artist='ENHYPEN', has_preview=True,
        deezer_id=deezer_id, deezer_artist_id=113915572, duration=duration,
    )


class FillerExclusionTests(TestCase):
    def test_directed_play_skips_filler(self) -> None:
        song = _track('Drunk-Dazed', 194, 1)
        _track('Voice Note (JAKE Ver.)', 36, 2)
        pool = catalog.playable(Track.objects.filter(deezer_artist_id=113915572), directed=True)
        self.assertEqual(list(pool), [song])

    def test_saving_a_duration_reclassifies(self) -> None:
        track = _track('Voice Note (JAKE Ver.)', None, 3)
        self.assertFalse(track.is_non_song)
        track.duration = 36
        track.save(update_fields=['duration'])
        track.refresh_from_db()
        self.assertTrue(track.is_non_song)

    def test_bulk_refresh_fills_duration_and_flag(self) -> None:
        track = _track('Voice Note (JAKE Ver.)', None, 4)
        catalog.bulk_upsert_tracks([{
            'title': track.title, 'artist': track.artist,
            'deezer_id': track.deezer_id, 'duration': 36,
        }])
        track.refresh_from_db()
        self.assertEqual(track.duration, 36)
        self.assertTrue(track.is_non_song)

    def test_bulk_create_flags_filler(self) -> None:
        catalog.bulk_upsert_tracks([{
            'title': 'Breaking News', 'artist': 'ENHYPEN', 'deezer_id': 5, 'duration': 49,
        }])
        self.assertTrue(Track.objects.get(deezer_id=5).is_non_song)


class AppVersionTests(TestCase):
    url = reverse('game:app_version')

    def test_unconfigured_means_no_check(self) -> None:
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {})

    def test_configured_platform(self) -> None:
        release = AppRelease.get_solo()
        release.latest_android_version = '2.3.4'
        release.save()
        self.assertEqual(self.client.get(self.url).json(), {
            'android': {
                'latest_version': '2.3.4',
                'store_url': 'https://play.google.com/store/apps/details?id=com.songspot.app',
            },
        })

    def test_version_without_store_link_is_not_enforced(self) -> None:
        release = AppRelease.get_solo()
        release.latest_ios_version = '2.3.4'
        release.save()
        self.assertEqual(self.client.get(self.url).json(), {})

    def test_ignores_an_invalid_session(self) -> None:
        response = self.client.get(self.url, HTTP_AUTHORIZATION='Bearer expired')
        self.assertEqual(response.status_code, 200)
