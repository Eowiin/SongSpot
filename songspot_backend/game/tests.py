from datetime import timedelta
from unittest.mock import patch

from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APITestCase
from rest_framework import status
from rest_framework_simplejwt.tokens import RefreshToken
from authentication.models import User
from .models import (
    Track, Room, RoomUser, DailySong, DailyGameSession,
    GuessAttempt, RoomMessage, SongPack, PackTrack, RoomPack
)


class TrackModelTests(TestCase):
    """Tests for the Track model."""

    def test_create_track(self):
        """Test creating a track."""
        track = Track.objects.create(
            title='Test Song',
            artist='Test Artist',
            preview_url='https://example.com/preview.mp3'
        )
        self.assertEqual(track.title, 'Test Song')
        self.assertEqual(track.artist, 'Test Artist')
        self.assertIsNotNone(track.id)

    def test_track_string_representation(self):
        """Test string representation of track."""
        track = Track.objects.create(
            title='Test Song',
            artist='Test Artist',
            preview_url='https://example.com/preview.mp3'
        )
        self.assertEqual(str(track), 'Test Song - Test Artist')


class RoomModelTests(TestCase):
    """Tests for the Room model."""

    def setUp(self):
        self.user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='testpass123'
        )

    def test_create_room(self):
        """Test creating a room."""
        room = Room.objects.create(host_user=self.user)
        self.assertIsNotNone(room.room_code)
        self.assertEqual(len(room.room_code), 6)
        self.assertEqual(room.host_user, self.user)

    def test_room_code_is_unique(self):
        """Test that room codes are auto-generated and unique."""
        room1 = Room.objects.create(host_user=self.user)
        room2 = Room.objects.create(host_user=self.user)
        self.assertNotEqual(room1.room_code, room2.room_code)

    def test_room_string_representation(self):
        """Test string representation of room."""
        room = Room.objects.create(host_user=self.user, name='Test Room')
        self.assertIn('Test Room', str(room))


class RoomCreateViewTests(APITestCase):
    """Tests for room creation endpoint."""

    def setUp(self):
        self.create_url = '/api/game/rooms/create/'
        self.user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='testpass123'
        )
        self.refresh = RefreshToken.for_user(self.user)
        self.access_token = str(self.refresh.access_token)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.access_token}')

    def test_create_room_success(self):
        """Test successful room creation."""
        response = self.client.post(self.create_url, {}, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertIn('room', response.data)
        self.assertIn('room_code', response.data['room'])
        self.assertEqual(len(response.data['room']['room_code']), 6)

    def test_create_room_user_added_automatically(self):
        """Test that creator is automatically added to room."""
        response = self.client.post(self.create_url, {}, format='json')
        room_id = response.data['room']['id']
        room = Room.objects.get(id=room_id)
        self.assertTrue(RoomUser.objects.filter(room=room, user=self.user).exists())

    def test_create_room_unauthenticated(self):
        """Test room creation fails without authentication."""
        self.client.credentials()
        response = self.client.post(self.create_url, {}, format='json')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    @override_settings(MAX_HOSTED_ROOMS_PER_USER=1, MAX_ROOM_CREATIONS_PER_DAY=5)
    def test_create_room_fails_when_hosted_room_limit_reached(self):
        """Test room creation fails when hosted room cap is reached."""
        Room.objects.create(host_user=self.user)
        response = self.client.post(self.create_url, {}, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Room limit reached', response.data.get('error', ''))

    @override_settings(MAX_HOSTED_ROOMS_PER_USER=50, MAX_ROOM_CREATIONS_PER_DAY=1)
    def test_create_room_fails_when_daily_creation_limit_reached(self):
        """Test room creation fails when daily creation cap is reached."""
        Room.objects.create(host_user=self.user)
        response = self.client.post(self.create_url, {}, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Daily room creation limit reached', response.data.get('error', ''))


class RoomJoinViewTests(APITestCase):
    """Tests for room joining endpoint."""

    def setUp(self):
        self.join_url = '/api/game/rooms/join/'
        self.host = User.objects.create_user(
            username='host',
            email='host@example.com',
            password='testpass123'
        )
        self.user = User.objects.create_user(
            username='joiner',
            email='joiner@example.com',
            password='testpass123'
        )
        self.room = Room.objects.create(host_user=self.host)
        RoomUser.objects.create(room=self.room, user=self.host)

        self.refresh = RefreshToken.for_user(self.user)
        self.access_token = str(self.refresh.access_token)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.access_token}')

    def test_join_room_success(self):
        """Test successful room joining."""
        data = {'room_code': self.room.room_code}
        response = self.client.post(self.join_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(RoomUser.objects.filter(room=self.room, user=self.user).exists())


class PackBundleSessionTests(APITestCase):
    """Tests for pack bundle gameplay."""

    def setUp(self):
        self.user = User.objects.create_user(
            username='bundleuser',
            email='bundle@example.com',
            password='testpass123'
        )
        self.room = Room.objects.create(host_user=self.user)
        RoomUser.objects.create(room=self.room, user=self.user)
        self.refresh = RefreshToken.for_user(self.user)
        self.access_token = str(self.refresh.access_token)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.access_token}')

        self.pack = SongPack.objects.create(name='Stem Pack', price_coins=0)
        self.track = Track.objects.create(
            title='Pack Song',
            artist='Pack Artist',
            preview_url='https://example.com/preview.mp3'
        )
        PackTrack.objects.create(
            pack=self.pack,
            track=self.track,
            order_in_pack=1,
            drums_url='https://example.com/drums.mp3',
            bass_url='https://example.com/bass.mp3',
            other_url='https://example.com/other.mp3',
            vocals_url='https://example.com/vocals.mp3',
        )
        RoomPack.objects.create(room=self.room, pack=self.pack, purchased_by=self.user)

    def test_start_bundle_session(self):
        url = f'/api/game/rooms/{self.room.id}/packs/{self.pack.id}/bundle/'
        response = self.client.get(url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('session', response.data)
        self.assertIn('stems', response.data)

    def test_guess_bundle_session(self):
        start_url = f'/api/game/rooms/{self.room.id}/packs/{self.pack.id}/bundle/'
        self.client.get(start_url)
        guess_url = f'/api/game/rooms/{self.room.id}/packs/{self.pack.id}/bundle/guess/'
        response = self.client.post(guess_url, {'track_id': str(self.track.id)}, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['is_correct'])

    def test_wrong_guess_on_final_stage_prompts_retry_flow(self):
        start_url = f'/api/game/rooms/{self.room.id}/packs/{self.pack.id}/bundle/'
        self.client.get(start_url)
        wrong_track = Track.objects.create(
            title='Wrong Song',
            artist='Wrong Artist',
            preview_url='https://example.com/wrong.mp3'
        )
        session = PackBundleSession.objects.get(room=self.room, user=self.user, pack=self.pack)
        session.current_stage = len(PACK_BUNDLE_STAGE_ORDER)
        session.save(update_fields=['current_stage'])

        guess_url = f'/api/game/rooms/{self.room.id}/packs/{self.pack.id}/bundle/guess/'
        response = self.client.post(guess_url, {'track_id': str(wrong_track.id)}, format='json')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data['is_correct'])
        self.assertFalse(response.data['game_over'])
        self.assertTrue(response.data['session']['retry_available'])
        self.assertEqual(response.data['session']['next_retry_requirement'], 'ad')

    def test_pack_retry_ad_then_wrong_guess_requests_coin_retry(self):
        start_url = f'/api/game/rooms/{self.room.id}/packs/{self.pack.id}/bundle/'
        self.client.get(start_url)
        wrong_track = Track.objects.create(
            title='Wrong Song',
            artist='Wrong Artist',
            preview_url='https://example.com/wrong.mp3'
        )
        session = PackBundleSession.objects.get(room=self.room, user=self.user, pack=self.pack)
        session.current_stage = len(PACK_BUNDLE_STAGE_ORDER)
        session.awaiting_retry_unlock = True
        session.save(update_fields=['current_stage', 'awaiting_retry_unlock'])

        retry_url = f'/api/game/rooms/{self.room.id}/packs/{self.pack.id}/bundle/retry/'
        retry_response = self.client.post(retry_url, {'action': 'ad'}, format='json')
        self.assertEqual(retry_response.status_code, status.HTTP_200_OK)
        self.assertEqual(retry_response.data['session']['retry_credits'], 1)

        guess_url = f'/api/game/rooms/{self.room.id}/packs/{self.pack.id}/bundle/guess/'
        wrong_again = self.client.post(guess_url, {'track_id': str(wrong_track.id)}, format='json')
        self.assertEqual(wrong_again.status_code, status.HTTP_200_OK)
        self.assertFalse(wrong_again.data['game_over'])
        self.assertEqual(
            wrong_again.data['session']['next_retry_requirement'],
            'coins',
        )

    def test_pack_retry_forfeit_ends_challenge(self):
        start_url = f'/api/game/rooms/{self.room.id}/packs/{self.pack.id}/bundle/'
        self.client.get(start_url)
        session = PackBundleSession.objects.get(room=self.room, user=self.user, pack=self.pack)
        session.current_stage = len(PACK_BUNDLE_STAGE_ORDER)
        session.awaiting_retry_unlock = True
        session.save(update_fields=['current_stage', 'awaiting_retry_unlock'])

        retry_url = f'/api/game/rooms/{self.room.id}/packs/{self.pack.id}/bundle/retry/'
        response = self.client.post(retry_url, {'action': 'forfeit'}, format='json')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['game_over'])
        self.assertIsNotNone(response.data['session']['completed_at'])

    def test_skip_last_stage_requires_guess(self):
        start_url = f'/api/game/rooms/{self.room.id}/packs/{self.pack.id}/bundle/'
        self.client.get(start_url)
        skip_url = f'/api/game/rooms/{self.room.id}/packs/{self.pack.id}/bundle/skip/'

        # Stage 1 -> 2 -> 3 -> 4 is allowed
        self.assertEqual(self.client.post(skip_url, {}, format='json').status_code, status.HTTP_200_OK)
        self.assertEqual(self.client.post(skip_url, {}, format='json').status_code, status.HTTP_200_OK)
        self.assertEqual(self.client.post(skip_url, {}, format='json').status_code, status.HTTP_200_OK)

        # Stage 4 cannot be skipped
        response = self.client.post(skip_url, {}, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(
            response.data.get('error'),
            'You must submit a guess on the last stage',
        )

        session = PackBundleSession.objects.get(
            room=self.room,
            user=self.user,
            pack=self.pack,
        )
        self.assertEqual(session.current_stage, len(PACK_BUNDLE_STAGE_ORDER))
        self.assertIsNone(session.completed_at)



    def test_join_room_already_member(self):
        """Test joining room fails if already a member."""
        RoomUser.objects.create(room=self.room, user=self.user)
        data = {'room_code': self.room.room_code}
        response = self.client.post(self.join_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_join_room_invalid_code(self):
        """Test joining room fails with invalid code."""
        data = {'room_code': 'INVALID'}
        response = self.client.post(self.join_url, data, format='json')
        # API returns 400 (validation) or 404 (not found) depending on implementation
        self.assertIn(response.status_code, [status.HTTP_400_BAD_REQUEST, status.HTTP_404_NOT_FOUND])


class RoomLeaveViewTests(APITestCase):
    """Tests for room leaving endpoint."""

    def setUp(self):
        self.host = User.objects.create_user(
            username='host',
            email='host@example.com',
            password='testpass123'
        )
        self.user = User.objects.create_user(
            username='member',
            email='member@example.com',
            password='testpass123'
        )
        self.room = Room.objects.create(host_user=self.host)
        RoomUser.objects.create(room=self.room, user=self.host)
        RoomUser.objects.create(room=self.room, user=self.user)

        self.leave_url = f'/api/game/rooms/{self.room.id}/leave/'
        self.refresh = RefreshToken.for_user(self.user)
        self.access_token = str(self.refresh.access_token)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.access_token}')

    def test_leave_room_success(self):
        """Test successful room leaving."""
        response = self.client.post(self.leave_url, {}, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(RoomUser.objects.filter(room=self.room, user=self.user).exists())

    def test_leave_room_not_member(self):
        """Test leaving room fails if not a member."""
        other_user = User.objects.create_user(
            username='other',
            email='other@example.com',
            password='testpass123'
        )
        other_refresh = RefreshToken.for_user(other_user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {str(other_refresh.access_token)}')
        response = self.client.post(self.leave_url, {}, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_leave_room_host_transfers(self):
        """Test that host role transfers when host leaves."""
        host_refresh = RefreshToken.for_user(self.host)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {str(host_refresh.access_token)}')
        response = self.client.post(self.leave_url, {}, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.room.refresh_from_db()
        self.assertEqual(self.room.host_user, self.user)

    def test_leave_room_deletes_when_empty(self):
        """Test that room is deleted when last user leaves."""
        # Remove the other user first
        RoomUser.objects.filter(room=self.room, user=self.user).delete()

        # Now host leaves
        host_refresh = RefreshToken.for_user(self.host)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {str(host_refresh.access_token)}')
        response = self.client.post(self.leave_url, {}, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(Room.objects.filter(id=self.room.id).exists())


class RoomRenameViewTests(APITestCase):
    """Tests for room renaming endpoint."""

    def setUp(self):
        self.host = User.objects.create_user(
            username='host',
            email='host@example.com',
            password='testpass123'
        )
        self.member = User.objects.create_user(
            username='member',
            email='member@example.com',
            password='testpass123'
        )
        self.room = Room.objects.create(host_user=self.host)
        RoomUser.objects.create(room=self.room, user=self.host)
        RoomUser.objects.create(room=self.room, user=self.member)

        self.rename_url = f'/api/game/rooms/{self.room.id}/rename/'
        self.refresh = RefreshToken.for_user(self.host)
        self.access_token = str(self.refresh.access_token)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.access_token}')

    def test_rename_room_success(self):
        """Test successful room renaming by host."""
        data = {'name': 'New Room Name'}
        response = self.client.put(self.rename_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.room.refresh_from_db()
        self.assertEqual(self.room.name, 'New Room Name')

    def test_rename_room_non_host_fails(self):
        """Test that non-host cannot rename room."""
        member_refresh = RefreshToken.for_user(self.member)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {str(member_refresh.access_token)}')
        data = {'name': 'Unauthorized Name'}
        response = self.client.put(self.rename_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)


class MyRoomsViewTests(APITestCase):
    """Tests for my rooms endpoint."""

    def setUp(self):
        self.my_rooms_url = '/api/game/rooms/my-rooms/'
        self.user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='testpass123'
        )
        self.other_user = User.objects.create_user(
            username='other',
            email='other@example.com',
            password='testpass123'
        )

        # Create rooms user is in
        self.room1 = Room.objects.create(host_user=self.user)
        RoomUser.objects.create(room=self.room1, user=self.user)

        self.room2 = Room.objects.create(host_user=self.other_user)
        RoomUser.objects.create(room=self.room2, user=self.other_user)
        RoomUser.objects.create(room=self.room2, user=self.user)

        # Room user is not in
        self.room3 = Room.objects.create(host_user=self.other_user)
        RoomUser.objects.create(room=self.room3, user=self.other_user)

        self.refresh = RefreshToken.for_user(self.user)
        self.access_token = str(self.refresh.access_token)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.access_token}')

    def test_get_my_rooms(self):
        """Test getting user's rooms."""
        response = self.client.get(self.my_rooms_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 2)  # User is in 2 rooms


class DailyGameViewTests(APITestCase):
    """Tests for daily game endpoints."""

    def setUp(self):
        self.user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='testpass123'
        )
        self.room = Room.objects.create(host_user=self.user)
        RoomUser.objects.create(room=self.room, user=self.user)

        self.track = Track.objects.create(
            title='Test Song',
            artist='Test Artist',
            preview_url='https://example.com/preview.mp3'
        )

        self.daily_game_url = f'/api/game/rooms/{self.room.id}/daily-game/'
        self.refresh = RefreshToken.for_user(self.user)
        self.access_token = str(self.refresh.access_token)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.access_token}')

    def test_get_daily_game_creates_session(self):
        """Test that getting daily game creates a session."""
        response = self.client.get(self.daily_game_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(DailyGameSession.objects.filter(room=self.room, user=self.user).exists())

    def test_get_daily_game_returns_existing_session(self):
        """Test that getting daily game returns existing session."""
        # Create first session
        response1 = self.client.get(self.daily_game_url)
        session_id = response1.data['id']

        # Get again - should return same session
        response2 = self.client.get(self.daily_game_url)
        self.assertEqual(response2.data['id'], session_id)

    def test_daily_game_non_member_fails(self):
        """Test that non-members cannot access daily game."""
        other_user = User.objects.create_user(
            username='other',
            email='other@example.com',
            password='testpass123'
        )
        other_refresh = RefreshToken.for_user(other_user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {str(other_refresh.access_token)}')
        response = self.client.get(self.daily_game_url)
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)


class SkipSnippetViewTests(APITestCase):
    """Tests for skip snippet endpoint."""

    def setUp(self):
        self.user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='testpass123'
        )
        self.room = Room.objects.create(host_user=self.user)
        RoomUser.objects.create(room=self.room, user=self.user)

        self.track = Track.objects.create(
            title='Test Song',
            artist='Test Artist',
            preview_url='https://example.com/preview.mp3'
        )

        today = timezone.now().date()
        self.daily_song = DailySong.objects.create(
            room=self.room,
            track=self.track,
            date=today
        )
        self.game_session = DailyGameSession.objects.create(
            room=self.room,
            user=self.user,
            daily_song=self.daily_song,
            current_snippet=1
        )

        self.skip_url = f'/api/game/rooms/{self.room.id}/daily-game/skip/'
        self.refresh = RefreshToken.for_user(self.user)
        self.access_token = str(self.refresh.access_token)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.access_token}')

    def test_skip_snippet_success(self):
        """Test successful snippet skip."""
        response = self.client.post(self.skip_url, {}, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['current_snippet'], 2)

    def test_skip_at_max_snippet_fails(self):
        """Test skip fails at maximum snippet."""
        self.game_session.current_snippet = 6
        self.game_session.save()
        response = self.client.post(self.skip_url, {}, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_skip_after_correct_guess_fails(self):
        """Test skip fails after correct guess."""
        self.game_session.correct_guess = True
        self.game_session.save()
        response = self.client.post(self.skip_url, {}, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    @patch('game.views._broadcast_leaderboard_updated')
    def test_skip_to_final_snippet_broadcasts_leaderboard_update(self, mock_broadcast):
        """Entering snippet 6 should trigger realtime results refresh."""
        self.game_session.current_snippet = 5
        self.game_session.save(update_fields=['current_snippet'])

        response = self.client.post(self.skip_url, {}, format='json')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['current_snippet'], 6)
        mock_broadcast.assert_called_once_with(self.room.id, self.user.id)


class SubmitGuessViewTests(APITestCase):
    """Tests for submit guess endpoint."""

    def setUp(self):
        self.user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='testpass123'
        )
        self.room = Room.objects.create(host_user=self.user)
        RoomUser.objects.create(room=self.room, user=self.user)

        self.correct_track = Track.objects.create(
            title='Correct Song',
            artist='Correct Artist',
            preview_url='https://example.com/correct.mp3'
        )
        self.wrong_track = Track.objects.create(
            title='Wrong Song',
            artist='Wrong Artist',
            preview_url='https://example.com/wrong.mp3'
        )

        today = timezone.now().date()
        self.daily_song = DailySong.objects.create(
            room=self.room,
            track=self.correct_track,
            date=today
        )
        self.game_session = DailyGameSession.objects.create(
            room=self.room,
            user=self.user,
            daily_song=self.daily_song,
            current_snippet=1
        )

        self.guess_url = f'/api/game/rooms/{self.room.id}/daily-game/guess/'
        self.retry_url = f'/api/game/rooms/{self.room.id}/daily-game/retry/'
        self.refresh = RefreshToken.for_user(self.user)
        self.access_token = str(self.refresh.access_token)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.access_token}')

    def test_correct_guess_first_snippet(self):
        """Test correct guess on first snippet awards 6 points."""
        data = {'track_id': str(self.correct_track.id)}
        response = self.client.post(self.guess_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['is_correct'])
        self.assertEqual(response.data['points_earned'], 6)

    def test_correct_guess_later_snippet(self):
        """Test correct guess on later snippet awards fewer points."""
        self.game_session.current_snippet = 4
        self.game_session.save()
        data = {'track_id': str(self.correct_track.id)}
        response = self.client.post(self.guess_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['is_correct'])
        self.assertEqual(response.data['points_earned'], 3)

    def test_wrong_guess_advances_snippet(self):
        """Test wrong guess advances to next snippet."""
        data = {'track_id': str(self.wrong_track.id)}
        response = self.client.post(self.guess_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data['is_correct'])
        self.assertEqual(response.data['current_snippet'], 2)

    @patch('game.views._broadcast_leaderboard_updated')
    def test_wrong_guess_to_final_snippet_broadcasts_leaderboard_update(self, mock_broadcast):
        """Reaching snippet 6 via wrong guess should refresh results in realtime."""
        self.game_session.current_snippet = 5
        self.game_session.save(update_fields=['current_snippet'])

        response = self.client.post(
            self.guess_url,
            {'track_id': str(self.wrong_track.id)},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data['is_correct'])
        self.assertEqual(response.data['current_snippet'], 6)
        mock_broadcast.assert_called_once_with(self.room.id, self.user.id)

    def test_wrong_guess_at_max_snippet(self):
        """Test wrong guess at max snippet prompts retry flow first."""
        self.game_session.current_snippet = 6
        self.game_session.save()
        data = {'track_id': str(self.wrong_track.id)}
        response = self.client.post(self.guess_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data['is_correct'])
        self.assertFalse(response.data['game_over'])
        self.assertTrue(response.data['retry_available'])
        self.assertEqual(response.data['next_retry_requirement'], 'ad')

    def test_retry_ad_then_wrong_guess_requests_coin_retry(self):
        """First retry is ad-gated, then next retry becomes coin-gated."""
        self.game_session.current_snippet = 6
        self.game_session.save(update_fields=['current_snippet'])

        self.client.post(self.guess_url, {'track_id': str(self.wrong_track.id)}, format='json')
        retry_response = self.client.post(self.retry_url, {'action': 'ad'}, format='json')
        self.assertEqual(retry_response.status_code, status.HTTP_200_OK)
        self.assertEqual(retry_response.data['retry_credits'], 1)

        wrong_again = self.client.post(self.guess_url, {'track_id': str(self.wrong_track.id)}, format='json')
        self.assertEqual(wrong_again.status_code, status.HTTP_200_OK)
        self.assertFalse(wrong_again.data['game_over'])
        self.assertEqual(wrong_again.data['next_retry_requirement'], 'coins')

    def test_retry_unlock_before_failure_fails(self):
        """Retry unlock cannot be used until a failed guess requests it."""
        self.game_session.current_snippet = 6
        self.game_session.save(update_fields=['current_snippet'])

        response = self.client.post(self.retry_url, {'action': 'ad'}, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_forfeit_ends_game_immediately(self):
        """Player can skip extra chance and go directly to results."""
        self.game_session.current_snippet = 6
        self.game_session.awaiting_retry_unlock = True
        self.game_session.save(update_fields=['current_snippet', 'awaiting_retry_unlock'])

        response = self.client.post(self.retry_url, {'action': 'forfeit'}, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['game_over'])
        self.assertEqual(response.data['points_earned'], 0)
        self.assertIn('correct_answer', response.data)

    def test_guess_after_completion_fails(self):
        """Test guessing after already completing fails."""
        self.game_session.correct_guess = True
        self.game_session.save()
        data = {'track_id': str(self.correct_track.id)}
        response = self.client.post(self.guess_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_guess_creates_attempt_record(self):
        """Test that guessing creates a GuessAttempt record."""
        data = {'track_id': str(self.wrong_track.id)}
        self.client.post(self.guess_url, data, format='json')
        self.assertTrue(GuessAttempt.objects.filter(game_session=self.game_session).exists())

    @override_settings(DAILY_GAME_MAX_RETRIES=0)
    @patch('game.views._broadcast_leaderboard_updated')
    def test_failed_guess_broadcasts_leaderboard_update(self, mock_broadcast):
        """Failed completion should trigger real-time leaderboard refresh."""
        self.game_session.current_snippet = 6
        self.game_session.save(update_fields=['current_snippet'])

        response = self.client.post(
            self.guess_url,
            {'track_id': str(self.wrong_track.id)},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['game_over'])
        self.assertEqual(response.data['points_earned'], 0)
        mock_broadcast.assert_called_once_with(self.room.id, self.user.id)


class LeaderboardViewTests(APITestCase):
    """Tests for leaderboard endpoint."""

    def setUp(self):
        self.user1 = User.objects.create_user(
            username='user1',
            email='user1@example.com',
            password='testpass123'
        )
        self.user2 = User.objects.create_user(
            username='user2',
            email='user2@example.com',
            password='testpass123'
        )
        self.room = Room.objects.create(host_user=self.user1)
        RoomUser.objects.create(room=self.room, user=self.user1)
        RoomUser.objects.create(room=self.room, user=self.user2)

        self.track = Track.objects.create(
            title='Test Song',
            artist='Test Artist',
            preview_url='https://example.com/preview.mp3'
        )

        today = timezone.now().date()
        self.daily_song = DailySong.objects.create(
            room=self.room,
            track=self.track,
            date=today
        )

        # User1 got 6 points
        DailyGameSession.objects.create(
            room=self.room,
            user=self.user1,
            daily_song=self.daily_song,
            current_snippet=1,
            correct_guess=True,
            points_earned=6,
            completed_at=timezone.now()
        )

        # User2 got 4 points
        DailyGameSession.objects.create(
            room=self.room,
            user=self.user2,
            daily_song=self.daily_song,
            current_snippet=3,
            correct_guess=True,
            points_earned=4,
            completed_at=timezone.now()
        )

        self.leaderboard_url = f'/api/game/rooms/{self.room.id}/daily-game/leaderboard/'
        self.refresh = RefreshToken.for_user(self.user1)
        self.access_token = str(self.refresh.access_token)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.access_token}')

    def test_get_leaderboard(self):
        """Test getting leaderboard."""
        response = self.client.get(self.leaderboard_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data['leaderboard']), 2)
        # First place should have 6 points
        self.assertEqual(response.data['leaderboard'][0]['points_earned'], 6)

    def test_leaderboard_includes_failed_players(self):
        """Completed failed attempts should also appear in today's results."""
        user3 = User.objects.create_user(
            username='user3',
            email='user3@example.com',
            password='testpass123'
        )
        RoomUser.objects.create(room=self.room, user=user3)
        DailyGameSession.objects.create(
            room=self.room,
            user=user3,
            daily_song=self.daily_song,
            current_snippet=6,
            correct_guess=False,
            points_earned=0,
            completed_at=timezone.now()
        )

        response = self.client.get(self.leaderboard_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data['leaderboard']), 3)

        failed_entry = next(
            item for item in response.data['leaderboard']
            if item['user']['username'] == 'user3'
        )
        self.assertFalse(failed_entry['correct_guess'])
        self.assertEqual(failed_entry['points_earned'], 0)

    def test_leaderboard_orders_winners_before_failed_players(self):
        """Successful guesses should rank above failed runs."""
        user3 = User.objects.create_user(
            username='user3',
            email='user3@example.com',
            password='testpass123'
        )
        RoomUser.objects.create(room=self.room, user=user3)
        DailyGameSession.objects.create(
            room=self.room,
            user=user3,
            daily_song=self.daily_song,
            current_snippet=6,
            correct_guess=False,
            points_earned=0,
            completed_at=timezone.now()
        )

        response = self.client.get(self.leaderboard_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        usernames = [entry['user']['username'] for entry in response.data['leaderboard']]
        self.assertEqual(usernames[-1], 'user3')

    def test_leaderboard_non_member_fails(self):
        """Test that non-members cannot view leaderboard."""
        other_user = User.objects.create_user(
            username='other',
            email='other@example.com',
            password='testpass123'
        )
        other_refresh = RefreshToken.for_user(other_user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {str(other_refresh.access_token)}')
        response = self.client.get(self.leaderboard_url)
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_leaderboard_includes_final_snippet_incomplete_failures(self):
        """Snippet-6 non-winners should appear in today's results."""
        user3 = User.objects.create_user(
            username='user3_final_snippet',
            email='user3_final_snippet@example.com',
            password='testpass123'
        )
        RoomUser.objects.create(room=self.room, user=user3)
        DailyGameSession.objects.create(
            room=self.room,
            user=user3,
            daily_song=self.daily_song,
            current_snippet=6,
            guesses_made=2,
            correct_guess=False,
            points_earned=None,
            completed_at=None
        )

        response = self.client.get(self.leaderboard_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data['leaderboard']), 3)
        entry = next(
            item for item in response.data['leaderboard']
            if item['user']['username'] == 'user3_final_snippet'
        )
        self.assertFalse(entry['correct_guess'])
        self.assertEqual(entry['points_earned'], 0)
        self.assertIsNotNone(entry['completed_at'])


class RoomHistoryDetailViewTests(APITestCase):
    """Tests for room history detail endpoint."""

    def setUp(self):
        self.user1 = User.objects.create_user(
            username='history_user1',
            email='history_user1@example.com',
            password='testpass123'
        )
        self.user2 = User.objects.create_user(
            username='history_user2',
            email='history_user2@example.com',
            password='testpass123'
        )
        self.room = Room.objects.create(host_user=self.user1)
        RoomUser.objects.create(room=self.room, user=self.user1)
        RoomUser.objects.create(room=self.room, user=self.user2)

        self.track = Track.objects.create(
            title='History Song',
            artist='History Artist',
            preview_url='https://example.com/history.mp3'
        )
        self.history_date = timezone.now().date() - timedelta(days=2)
        self.daily_song = DailySong.objects.create(
            room=self.room,
            track=self.track,
            date=self.history_date,
        )

        DailyGameSession.objects.create(
            room=self.room,
            user=self.user1,
            daily_song=self.daily_song,
            current_snippet=2,
            correct_guess=True,
            points_earned=5,
            completed_at=timezone.now() - timedelta(minutes=5),
        )
        DailyGameSession.objects.create(
            room=self.room,
            user=self.user2,
            daily_song=self.daily_song,
            current_snippet=6,
            correct_guess=False,
            points_earned=0,
            completed_at=timezone.now(),
        )

        self.detail_url = f'/api/game/rooms/{self.room.id}/history/{self.history_date.isoformat()}/'
        refresh = RefreshToken.for_user(self.user1)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {str(refresh.access_token)}')

    def test_history_detail_includes_failed_players(self):
        """History leaderboard should include completed failed attempts."""
        response = self.client.get(self.detail_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data['leaderboard']), 2)

        failed_entry = next(
            item for item in response.data['leaderboard']
            if item['user']['username'] == 'history_user2'
        )
        self.assertFalse(failed_entry['correct_guess'])
        self.assertEqual(failed_entry['points_earned'], 0)

    def test_history_detail_orders_winners_before_failed_players(self):
        """Winners should remain ranked above failed attempts in history."""
        response = self.client.get(self.detail_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        usernames = [entry['user']['username'] for entry in response.data['leaderboard']]
        self.assertEqual(usernames, ['history_user1', 'history_user2'])


class RoomMessagesViewTests(APITestCase):
    """Tests for room messages endpoint."""

    def setUp(self):
        self.user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='testpass123'
        )
        self.room = Room.objects.create(host_user=self.user)
        RoomUser.objects.create(room=self.room, user=self.user)

        self.messages_url = f'/api/game/rooms/{self.room.id}/messages/'
        self.refresh = RefreshToken.for_user(self.user)
        self.access_token = str(self.refresh.access_token)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.access_token}')

    def test_post_message_success(self):
        """Test posting a message."""
        data = {'message': 'Hello everyone!'}
        response = self.client.post(self.messages_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(RoomMessage.objects.filter(room=self.room, message='Hello everyone!').exists())

    def test_get_messages(self):
        """Test getting messages."""
        RoomMessage.objects.create(room=self.room, user=self.user, message='Test message')
        response = self.client.get(self.messages_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data['messages']), 1)

    def test_post_message_non_member_fails(self):
        """Test that non-members cannot post messages."""
        other_user = User.objects.create_user(
            username='other',
            email='other@example.com',
            password='testpass123'
        )
        other_refresh = RefreshToken.for_user(other_user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {str(other_refresh.access_token)}')
        data = {'message': 'Unauthorized message'}
        response = self.client.post(self.messages_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_message_max_length(self):
        """Test that messages over 500 chars are rejected."""
        data = {'message': 'x' * 501}
        response = self.client.post(self.messages_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class SearchTracksViewTests(APITestCase):
    """Tests for track search endpoint."""

    def setUp(self):
        self.search_url = '/api/game/tracks/search/'
        self.user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='testpass123'
        )

        Track.objects.create(title='Bohemian Rhapsody', artist='Queen', preview_url='https://example.com/1.mp3')
        Track.objects.create(title='Stairway to Heaven', artist='Led Zeppelin', preview_url='https://example.com/2.mp3')
        Track.objects.create(title='Hotel California', artist='Eagles', preview_url='https://example.com/3.mp3')

        self.refresh = RefreshToken.for_user(self.user)
        self.access_token = str(self.refresh.access_token)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.access_token}')

    def test_search_by_title(self):
        """Test searching tracks by title."""
        response = self.client.get(f'{self.search_url}?q=bohemian')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]['title'], 'Bohemian Rhapsody')

    def test_search_by_artist(self):
        """Test searching tracks by artist."""
        response = self.client.get(f'{self.search_url}?q=queen')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)

    def test_search_empty_query(self):
        """Test search with empty query returns empty list."""
        response = self.client.get(f'{self.search_url}?q=')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 0)

    def test_search_no_matches(self):
        """Test search with no matches returns empty list."""
        response = self.client.get(f'{self.search_url}?q=nonexistent')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 0)

    def test_search_default_limit_allows_more_than_ten_results(self):
        """Default search limit should not truncate common artist queries at 10."""
        artist_name = 'TestArtistMany'
        for i in range(12):
            Track.objects.create(
                title=f'Song {i}',
                artist=artist_name,
                preview_url=f'https://example.com/many-{i}.mp3',
            )

        response = self.client.get(f'{self.search_url}?q={artist_name}')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 12)

    def test_search_limit_query_param_is_respected(self):
        """Search should honor explicit limit query param."""
        artist_name = 'TestArtistLimit'
        for i in range(20):
            Track.objects.create(
                title=f'Limit Song {i}',
                artist=artist_name,
                preview_url=f'https://example.com/limit-{i}.mp3',
            )

        response = self.client.get(f'{self.search_url}?q={artist_name}&limit=8')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 8)
