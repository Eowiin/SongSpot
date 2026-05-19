"""WebSocket consumers for 1v1 duel mode."""

import asyncio
import json
import logging
import random
import time

from asgiref.sync import sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer
from django.db import transaction

from .models import DuelMatch, DuelRound, MatchmakingQueue, PlaylistTrack, Track, UserElo

logger = logging.getLogger(__name__)

ROUND_TIME_LIMIT = 60        # seconds per round
NEXT_ROUND_DELAY = 3         # seconds between round_result and next round_start
TOTAL_ROUNDS = 5
SNIPPET_POINTS = {1: 100, 2: 80, 3: 60, 4: 40, 5: 20}

# In-process state — works for single-worker ASGI (standard Daphne/Uvicorn setup)
_connected: dict[str, set] = {}         # match_id → {player_num, ...}
_round_timers: dict[str, asyncio.Task] = {}   # match_id → active timer Task
_resolved_rounds: dict[str, set] = {}   # match_id → {round_numbers already resolved}
_audio_ready: dict[str, set] = {}       # match_id → {player_nums who sent audio_ready}
_ready_timeouts: dict[str, asyncio.Task] = {}  # match_id → pending round_begin timeout task
_round_begun: dict[str, bool] = {}      # match_id → True once round_begin has been broadcast
_match_locks: dict[str, asyncio.Lock] = {}  # match_id → lock for round-start / resolve coordination
_round_started_at: dict[str, float] = {}    # match_id → unix time when current round timer started
_forfeit_tasks: dict[str, asyncio.Task] = {}  # "{match_id}_{player_num}" → pending forfeit task


def _parse_qs(scope) -> dict:
    """Parse query string from ASGI scope into a dict."""
    raw = scope.get('query_string', b'').decode()
    result = {}
    for part in raw.split('&'):
        if '=' in part:
            k, v = part.split('=', 1)
            result[k] = v
    return result


def _pick_tracks(playlist_id, count: int) -> list:
    """Synchronous: pick `count` distinct random tracks from the playlist (or all tracks)."""
    qs = Track.objects.filter(preview_url__isnull=False).exclude(preview_url='')
    if playlist_id:
        ids = PlaylistTrack.objects.filter(playlist_id=playlist_id).values_list('track_id', flat=True)
        qs = qs.filter(id__in=ids)
    total = qs.count()
    if total == 0:
        qs = Track.objects.filter(preview_url__isnull=False).exclude(preview_url='')
        total = qs.count()
    count = min(count, total)
    return list(qs.order_by('?')[:count])


# ─────────────────────────────────────────────────────────────────────────────
# Matchmaking
# ─────────────────────────────────────────────────────────────────────────────

class MatchmakingConsumer(AsyncWebsocketConsumer):
    """
    Handles matchmaking queue.  Connect with:
      ws/duel/queue/?token=<jwt>&playlist=<optional_uuid>
    Events sent to client:
      {type: "queued",      elo: <int>}
      {type: "match_found", match_id, opponent: {username, elo}, playlist: {id, name} | null}
    Events received from client:
      {type: "cancel"}
    """

    async def connect(self):
        user = self.scope['user']
        if not user.is_authenticated:
            await self.close(code=4001)
            return

        self.user = user
        self.personal_group = f'queue_user_{user.id}'
        self.matching_task = None

        qs = _parse_qs(self.scope)
        self.playlist_id = qs.get('playlist') or None

        await self.accept()
        await self.channel_layer.group_add(self.personal_group, self.channel_name)

        elo_obj = await self._get_or_create_elo()
        self.current_elo = elo_obj.elo

        await self._join_queue()
        await self.send(json.dumps({'type': 'queued', 'elo': self.current_elo}))

        self.matching_task = asyncio.create_task(self._match_loop())

    async def disconnect(self, code):
        if self.matching_task:
            self.matching_task.cancel()
        await self._leave_queue()
        await self.channel_layer.group_discard(self.personal_group, self.channel_name)

    async def receive(self, text_data):
        try:
            data = json.loads(text_data)
        except json.JSONDecodeError:
            return
        if data.get('type') == 'cancel':
            await self.close()

    async def match_found(self, event):
        """Dispatched by channel layer when a match is created."""
        await self.send(json.dumps({
            'type': 'match_found',
            'match_id': event['match_id'],
            'opponent': event['opponent'],
            'playlist': event['playlist'],
        }))

    # ── Matching loop ─────────────────────────────────────────────────────────

    async def _match_loop(self):
        elo_range = 100
        iterations = 0
        try:
            while True:
                await asyncio.sleep(5)
                iterations += 1
                if iterations % 6 == 0:  # every ~30s
                    elo_range += 50

                result = await self._try_create_match(elo_range)
                if result is None:
                    continue

                match, opponent_user, playlist = result

                opp_elo = await self._get_elo(opponent_user)
                playlist_data = {'id': str(playlist.id), 'name': playlist.name} if playlist else None

                await self.channel_layer.group_send(self.personal_group, {
                    'type': 'match_found',
                    'match_id': str(match.id),
                    'opponent': {'username': opponent_user.username, 'elo': opp_elo},
                    'playlist': playlist_data,
                })
                await self.channel_layer.group_send(f'queue_user_{opponent_user.id}', {
                    'type': 'match_found',
                    'match_id': str(match.id),
                    'opponent': {'username': self.user.username, 'elo': self.current_elo},
                    'playlist': playlist_data,
                })
                return
        except asyncio.CancelledError:
            pass

    # ── DB helpers ────────────────────────────────────────────────────────────

    @sync_to_async
    def _try_create_match(self, elo_range):
        with transaction.atomic():
            try:
                my_entry = MatchmakingQueue.objects.select_for_update(nowait=True).get(user=self.user)
            except MatchmakingQueue.DoesNotExist:
                return None
            except Exception:
                return None

            opp = (
                MatchmakingQueue.objects
                .select_for_update(skip_locked=True)
                .filter(
                    elo_at_join__gte=self.current_elo - elo_range,
                    elo_at_join__lte=self.current_elo + elo_range,
                )
                .exclude(user=self.user)
                .order_by('joined_at')
                .select_related('user', 'playlist')
                .first()
            )
            if not opp:
                return None

            playlist = my_entry.playlist or opp.playlist
            match = DuelMatch.objects.create(
                player1=self.user,
                player2=opp.user,
                playlist=playlist,
                status='waiting',
                total_rounds=TOTAL_ROUNDS,
            )
            tracks = _pick_tracks(playlist.id if playlist else None, TOTAL_ROUNDS)
            for i, track in enumerate(tracks, 1):
                DuelRound.objects.create(match=match, round_number=i, track=track)

            my_entry.delete()
            opp.delete()
            return match, opp.user, playlist

    @sync_to_async
    def _join_queue(self):
        MatchmakingQueue.objects.update_or_create(
            user=self.user,
            defaults={'elo_at_join': self.current_elo, 'playlist_id': self.playlist_id},
        )

    @sync_to_async
    def _leave_queue(self):
        MatchmakingQueue.objects.filter(user=self.user).delete()

    @sync_to_async
    def _get_or_create_elo(self):
        obj, _ = UserElo.objects.get_or_create(user=self.user, defaults={'elo': 1000})
        return obj

    @sync_to_async
    def _get_elo(self, user):
        obj, _ = UserElo.objects.get_or_create(user=user, defaults={'elo': 1000})
        return obj.elo


# ─────────────────────────────────────────────────────────────────────────────
# Duel game
# ─────────────────────────────────────────────────────────────────────────────

class DuelConsumer(AsyncWebsocketConsumer):
    """
    Handles a 1v1 duel match.  Connect with:
      ws/duel/<match_id>/?token=<jwt>

    Round coordination uses per-match asyncio locks (_match_locks) so either
    player's consumer can start/resolve rounds. The round timer survives a single
    player disconnect — only when both players are gone is the match abandoned.
    """

    async def connect(self):
        user = self.scope['user']
        if not user.is_authenticated:
            await self.close(code=4001)
            return

        self.match_id = str(self.scope['url_route']['kwargs']['match_id'])
        self.group_name = f'duel_{self.match_id}'

        match = await self._load_match()
        if match is None or not match.is_player(user):
            await self.close(code=4003)
            return

        self.user = user
        self.match = match
        self.player_num = 1 if match.player1_id == user.id else 2

        await self.accept()
        await self.channel_layer.group_add(self.group_name, self.channel_name)

        _connected.setdefault(self.match_id, set()).add(self.player_num)

        # Cancel any pending forfeit task for this player (they reconnected in time).
        forfeit_key = f'{self.match_id}_{self.player_num}'
        t = _forfeit_tasks.pop(forfeit_key, None)
        if t:
            t.cancel()

        if match.status == 'in_progress' and match.current_round > 0:
            # Reconnect: push current round state directly to this connection.
            await self._send_reconnect_state(match)
            # Notify the other player.
            await self.channel_layer.group_send(self.group_name, {
                'type': 'opponent_reconnected_event',
                'player_num': self.player_num,
            })
        else:
            await self.channel_layer.group_send(self.group_name, {
                'type': 'player_ready',
                'player_num': self.player_num,
            })

    async def disconnect(self, code):
        _connected.get(self.match_id, set()).discard(self.player_num)

        still_connected = _connected.get(self.match_id, set())

        await self.channel_layer.group_send(self.group_name, {
            'type': 'peer_disconnected',
            'player_num': self.player_num,
        })

        if not still_connected:
            # Both players gone — tear everything down.
            timer = _round_timers.pop(self.match_id, None)
            if timer:
                timer.cancel()
            ready_timeout = _ready_timeouts.pop(self.match_id, None)
            if ready_timeout:
                ready_timeout.cancel()
            for pnum in (1, 2):
                t = _forfeit_tasks.pop(f'{self.match_id}_{pnum}', None)
                if t:
                    t.cancel()
            await self._maybe_abandon()
        else:
            # One player still connected — schedule forfeit for the one who left.
            match = await self._load_match_fresh()
            if match and match.status == 'in_progress' and match.current_round > 0:
                self._schedule_forfeit(self.player_num, match.current_round)

        await self.channel_layer.group_discard(self.group_name, self.channel_name)

        # Cleanup in-process state when no one is left
        if not _connected.get(self.match_id):
            _connected.pop(self.match_id, None)
            _resolved_rounds.pop(self.match_id, None)
            _audio_ready.pop(self.match_id, None)
            _round_begun.pop(self.match_id, None)
            _match_locks.pop(self.match_id, None)
            _round_started_at.pop(self.match_id, None)

    async def receive(self, text_data):
        try:
            data = json.loads(text_data)
        except json.JSONDecodeError:
            return
        msg_type = data.get('type')
        if msg_type == 'submit_guess':
            await self._handle_submit_guess(data)
        elif msg_type == 'audio_ready':
            await self._handle_audio_ready()

    # ── Channel-layer event handlers ──────────────────────────────────────────

    async def player_ready(self, event):
        """Both players connected → first consumer to acquire the lock fires round 1."""
        connected = _connected.get(self.match_id, set())
        if {1, 2}.issubset(connected):
            lock = _match_locks.setdefault(self.match_id, asyncio.Lock())
            async with lock:
                match = await self._load_match_fresh()
                # Only start round 1 on a fresh match — not on reconnect.
                if (match and match.status == 'waiting' and match.current_round == 0
                        and self.match_id not in _round_timers
                        and not _ready_timeouts.get(self.match_id)):
                    await self._start_round(1)

    async def round_start_event(self, event):
        await self.send(json.dumps({
            'type': 'round_start',
            'round': event['round'],
            'track': event['track'],
            'time_limit': ROUND_TIME_LIMIT,
        }))

    async def round_begin_event(self, event):
        await self.send(json.dumps({
            'type': 'round_begin',
            'countdown': 3,
            'time_limit': event.get('time_limit', ROUND_TIME_LIMIT),
        }))

    async def opponent_submitted_event(self, event):
        if event['player_num'] != self.player_num:
            await self.send(json.dumps({'type': 'opponent_submitted'}))

        await self._check_and_resolve()

    async def round_result_event(self, event):
        is_p1 = self.player_num == 1
        await self.send(json.dumps({
            'type': 'round_result',
            'round': event['round'],
            'track': event['track'],
            'player': event['p1'] if is_p1 else event['p2'],
            'opponent': event['p2'] if is_p1 else event['p1'],
            'scores': {
                'player': event['scores']['p1'] if is_p1 else event['scores']['p2'],
                'opponent': event['scores']['p2'] if is_p1 else event['scores']['p1'],
            },
        }))

    async def match_end_event(self, event):
        is_p1 = self.player_num == 1
        winner_raw = event['winner']  # 'p1' | 'p2' | 'draw'
        if winner_raw == 'draw':
            my_winner = 'draw'
        elif (winner_raw == 'p1' and is_p1) or (winner_raw == 'p2' and not is_p1):
            my_winner = 'player'
        else:
            my_winner = 'opponent'

        await self.send(json.dumps({
            'type': 'match_end',
            'winner': my_winner,
            'final_scores': {
                'player': event['scores']['p1'] if is_p1 else event['scores']['p2'],
                'opponent': event['scores']['p2'] if is_p1 else event['scores']['p1'],
            },
            'elo_change': {
                'player': event['elo_changes']['p1'] if is_p1 else event['elo_changes']['p2'],
                'opponent': event['elo_changes']['p2'] if is_p1 else event['elo_changes']['p1'],
            },
            'new_elo': {
                'player': event['new_elos']['p1'] if is_p1 else event['new_elos']['p2'],
                'opponent': event['new_elos']['p2'] if is_p1 else event['new_elos']['p1'],
            },
        }))

    async def peer_disconnected(self, event):
        if event['player_num'] != self.player_num:
            await self.send(json.dumps({'type': 'opponent_disconnected'}))

    async def opponent_reconnected_event(self, event):
        if event['player_num'] != self.player_num:
            await self.send(json.dumps({'type': 'opponent_reconnected'}))

    # ── Game logic (only player 1 coordinates) ────────────────────────────────

    async def _start_round(self, round_number):
        round_obj = await self._get_round(round_number)
        if round_obj is None:
            return
        await self._db_set_current_round(round_number)

        # Refresh the preview URL so players never get a stale Deezer link.
        preview_url = await sync_to_async(round_obj.track.get_fresh_preview_url)(
            prefer_cached=False
        )

        # Reset audio-ready state for this round
        _audio_ready[self.match_id] = set()
        _round_begun[self.match_id] = False

        await self.channel_layer.group_send(self.group_name, {
            'type': 'round_start_event',
            'round': round_number,
            'track': {
                'id': str(round_obj.track.id),
                'preview_url': preview_url,
                'cover_url': round_obj.track.cover_url or '',
            },
        })

        # Wait up to 15s for both players to signal audio loaded, then fire round_begin
        timeout = asyncio.create_task(self._audio_ready_timeout(round_number))
        _ready_timeouts[self.match_id] = timeout

    async def _audio_ready_timeout(self, round_number):
        """Fires round_begin after 15s if both players haven't signalled audio_ready."""
        try:
            await asyncio.sleep(15)
            await self._fire_round_begin(round_number)
        except asyncio.CancelledError:
            pass

    async def _handle_audio_ready(self):
        match = await self._load_match_fresh()
        if match is None or match.current_round == 0:
            return
        round_number = match.current_round
        _audio_ready.setdefault(self.match_id, set()).add(self.player_num)
        connected = _connected.get(self.match_id, set())
        if connected and connected.issubset(_audio_ready.get(self.match_id, set())):
            timeout = _ready_timeouts.pop(self.match_id, None)
            if timeout:
                timeout.cancel()
            await self._fire_round_begin(round_number)

    async def _fire_round_begin(self, round_number):
        # Guard: check-and-set before any await so concurrent callers are safe
        if _round_begun.get(self.match_id):
            return
        _round_begun[self.match_id] = True

        await self.channel_layer.group_send(self.group_name, {
            'type': 'round_begin_event',
            'round': round_number,
            'time_limit': ROUND_TIME_LIMIT,
            'started_at': time.time(),
        })
        self._begin_round_timer(round_number)

        # If a player is already disconnected when the round begins, start their
        # forfeit immediately with the same grace-period logic.
        connected = _connected.get(self.match_id, set())
        for pnum in (1, 2):
            if pnum not in connected:
                self._schedule_forfeit(pnum, round_number)

    def _begin_round_timer(self, round_number):
        if self.match_id not in _round_timers:
            _round_started_at[self.match_id] = time.time()
            timer = asyncio.create_task(self._round_timer(round_number))
            _round_timers[self.match_id] = timer

    def _schedule_forfeit(self, player_num: int, round_number: int):
        key = f'{self.match_id}_{player_num}'
        existing = _forfeit_tasks.pop(key, None)
        if existing:
            existing.cancel()
        elapsed = time.time() - _round_started_at.get(self.match_id, time.time())
        remaining = max(0.0, ROUND_TIME_LIMIT - elapsed)
        grace = min(30.0, remaining)
        logger.info('[forfeit] scheduling p%s match=%s round=%s grace=%.1fs remaining=%.1fs',
                    player_num, self.match_id, round_number, grace, remaining)
        task = asyncio.create_task(self._forfeit_after(player_num, round_number, grace))
        _forfeit_tasks[key] = task

    async def _forfeit_after(self, player_num: int, round_number: int, delay: float):
        try:
            logger.info('[forfeit] scheduled p%s match=%s in %.1fs', player_num, self.match_id, delay)
            await asyncio.sleep(delay)
            logger.info('[forfeit] firing p%s match=%s round=%s', player_num, self.match_id, round_number)
            await self._forfeit_player(player_num, round_number)
        except asyncio.CancelledError:
            logger.info('[forfeit] cancelled p%s match=%s', player_num, self.match_id)
        except Exception:
            logger.exception('[forfeit] ERROR p%s match=%s round=%s', player_num, self.match_id, round_number)

    async def _forfeit_player(self, player_num: int, round_number: int):
        """Auto-submit 0 pts for a disconnected player, then resolve the round.
        Resolves immediately regardless of whether the other player submitted —
        they get credit for whatever they guessed (0 if they didn't)."""
        await self._db_forfeit_round(round_number, player_num)
        lock = _match_locks.setdefault(self.match_id, asyncio.Lock())
        async with lock:
            timer = _round_timers.pop(self.match_id, None)
            if timer:
                timer.cancel()
            await self._resolve_round(round_number)

    async def _send_reconnect_state(self, match):
        """Push current round state directly to a reconnecting player."""
        round_obj = await self._get_round(match.current_round)
        if round_obj is None:
            return

        elapsed = time.time() - _round_started_at.get(self.match_id, time.time())
        time_remaining = max(0, int(ROUND_TIME_LIMIT - elapsed))
        round_active = self.match_id in _round_timers
        logger.info('[reconnect] p%s match=%s round=%s round_active=%s time_remaining=%s',
                    self.player_num, self.match_id, match.current_round, round_active, time_remaining)

        is_p1 = self.player_num == 1
        await self.send(json.dumps({
            'type': 'reconnect_state',
            'round': match.current_round,
            'total_rounds': match.total_rounds,
            'track': {
                'id': str(round_obj.track.id),
                'preview_url': round_obj.track.preview_url,
                'cover_url': round_obj.track.cover_url or '',
            },
            'time_remaining': time_remaining if round_active else 0,
            'round_active': round_active,
            'scores': {
                'player': match.player1_score if is_p1 else match.player2_score,
                'opponent': match.player2_score if is_p1 else match.player1_score,
            },
        }))

    async def _round_timer(self, round_number):
        try:
            await asyncio.sleep(ROUND_TIME_LIMIT)
            logger.info('[timer] expired round=%s match=%s', round_number, self.match_id)
            _round_timers.pop(self.match_id, None)
            lock = _match_locks.setdefault(self.match_id, asyncio.Lock())
            async with lock:
                await self._resolve_round(round_number)
        except asyncio.CancelledError:
            pass
        except Exception:
            logger.exception('[timer] ERROR round=%s match=%s', round_number, self.match_id)

    async def _handle_submit_guess(self, data):
        match = await self._load_match_fresh()
        if match is None or match.status not in ('waiting', 'in_progress'):
            return

        round_number = match.current_round
        if round_number == 0:
            return

        round_obj = await self._get_round(round_number)
        if round_obj is None:
            return

        # Guard: already submitted
        if self.player_num == 1 and round_obj.player1_submitted_at is not None:
            return
        if self.player_num == 2 and round_obj.player2_submitted_at is not None:
            return

        track_id = str(data.get('track_id', ''))
        snippets_used = max(1, min(5, int(data.get('snippets_used', 1))))
        is_correct = track_id == str(round_obj.track_id)
        points = SNIPPET_POINTS.get(snippets_used, 0) if is_correct else 0

        await self._db_save_guess(round_obj.id, is_correct, points, snippets_used)

        await self.channel_layer.group_send(self.group_name, {
            'type': 'opponent_submitted_event',
            'player_num': self.player_num,
        })

        await self._check_and_resolve()

    async def _check_and_resolve(self):
        lock = _match_locks.setdefault(self.match_id, asyncio.Lock())
        async with lock:
            match = await self._load_match_fresh()
            if match is None:
                return
            round_obj = await self._get_round(match.current_round)
            if round_obj is None:
                return
            connected = _connected.get(self.match_id, set())
            should_resolve = (
                round_obj.both_submitted
                or (1 not in connected and round_obj.player2_submitted_at is not None)
                or (2 not in connected and round_obj.player1_submitted_at is not None)
            )
            if should_resolve:
                timer = _round_timers.pop(self.match_id, None)
                if timer:
                    timer.cancel()
                await self._resolve_round(match.current_round)

    async def _resolve_round(self, round_number):
        """Called under _match_locks. Belt-and-suspenders guard against double-resolve."""
        resolved = _resolved_rounds.setdefault(self.match_id, set())
        if round_number in resolved:
            return
        resolved.add(round_number)

        # Cancel any pending forfeit tasks for this round.
        for pnum in (1, 2):
            t = _forfeit_tasks.pop(f'{self.match_id}_{pnum}', None)
            if t:
                t.cancel()

        round_obj = await self._get_round(round_number)
        if round_obj is None:
            return

        match = await self._load_match_fresh()
        if match is None:
            return

        p1_pts = round_obj.player1_points   # 0 if didn't submit (default)
        p2_pts = round_obj.player2_points
        new_p1 = match.player1_score + p1_pts
        new_p2 = match.player2_score + p2_pts
        await self._db_update_scores(new_p1, new_p2)

        await self.channel_layer.group_send(self.group_name, {
            'type': 'round_result_event',
            'round': round_number,
            'track': {
                'title': round_obj.track.title,
                'artist': round_obj.track.artist,
                'cover_url': round_obj.track.cover_url or '',
            },
            'p1': {
                'correct': bool(round_obj.player1_correct),
                'points': p1_pts,
                'snippets_used': round_obj.player1_snippets_used,
            },
            'p2': {
                'correct': bool(round_obj.player2_correct),
                'points': p2_pts,
                'snippets_used': round_obj.player2_snippets_used,
            },
            'scores': {'p1': new_p1, 'p2': new_p2},
        })

        # Detach the sleep+transition so _resolve_round returns immediately.
        # When called from within an event handler (e.g. opponent_submitted_event),
        # Django Channels blocks the consumer's event queue until the handler
        # coroutine fully returns — meaning the round_result_event we just sent
        # to the group would pile up unprocessed behind the sleeping handler,
        # causing player 1 to receive round_result far too late (after round_start
        # for the next round has already arrived, cancelling the reveal overlay).
        async def _transition():
            await asyncio.sleep(NEXT_ROUND_DELAY)
            if round_number >= match.total_rounds:
                await self._end_match(new_p1, new_p2)
            else:
                await self._start_round(round_number + 1)

        asyncio.create_task(_transition())

    async def _end_match(self, p1_score, p2_score):
        if p1_score > p2_score:
            p1_result, p2_result, winner_str, winner_id = 'win', 'loss', 'p1', self.match.player1_id
        elif p2_score > p1_score:
            p1_result, p2_result, winner_str, winner_id = 'loss', 'win', 'p2', self.match.player2_id
        else:
            p1_result, p2_result, winner_str, winner_id = 'draw', 'draw', 'draw', None

        p1_elo, p2_elo, p1_change, p2_change = await self._db_update_elos(p1_result, p2_result)
        await self._db_finalize(winner_id)

        await self.channel_layer.group_send(self.group_name, {
            'type': 'match_end_event',
            'winner': winner_str,
            'scores': {'p1': p1_score, 'p2': p2_score},
            'elo_changes': {'p1': p1_change, 'p2': p2_change},
            'new_elos': {'p1': p1_elo, 'p2': p2_elo},
        })

    # ── DB helpers ────────────────────────────────────────────────────────────

    @sync_to_async
    def _load_match(self):
        try:
            return DuelMatch.objects.select_related('player1', 'player2').get(id=self.match_id)
        except DuelMatch.DoesNotExist:
            return None

    @sync_to_async
    def _load_match_fresh(self):
        try:
            return DuelMatch.objects.get(id=self.match_id)
        except DuelMatch.DoesNotExist:
            return None

    @sync_to_async
    def _get_round(self, round_number):
        try:
            return DuelRound.objects.select_related('track').get(
                match_id=self.match_id, round_number=round_number,
            )
        except DuelRound.DoesNotExist:
            return None

    @sync_to_async
    def _db_set_current_round(self, round_number):
        DuelMatch.objects.filter(id=self.match_id).update(
            current_round=round_number, status='in_progress',
        )

    @sync_to_async
    def _db_save_guess(self, round_id, is_correct, points, snippets_used):
        from django.utils import timezone as tz
        now = tz.now()
        if self.player_num == 1:
            DuelRound.objects.filter(id=round_id, player1_submitted_at__isnull=True).update(
                player1_correct=is_correct,
                player1_points=points,
                player1_snippets_used=snippets_used,
                player1_submitted_at=now,
            )
        else:
            DuelRound.objects.filter(id=round_id, player2_submitted_at__isnull=True).update(
                player2_correct=is_correct,
                player2_points=points,
                player2_snippets_used=snippets_used,
                player2_submitted_at=now,
            )

    @sync_to_async
    def _db_update_scores(self, p1_score, p2_score):
        DuelMatch.objects.filter(id=self.match_id).update(
            player1_score=p1_score, player2_score=p2_score,
        )

    @sync_to_async
    def _db_update_elos(self, p1_result, p2_result):
        with transaction.atomic():
            p1_obj, _ = UserElo.objects.select_for_update().get_or_create(
                user_id=self.match.player1_id, defaults={'elo': 1000},
            )
            p2_obj, _ = UserElo.objects.select_for_update().get_or_create(
                user_id=self.match.player2_id, defaults={'elo': 1000},
            )
            old_p1, old_p2 = p1_obj.elo, p2_obj.elo
            p1_obj.update(opponent_elo=old_p2, result=p1_result)
            p2_obj.update(opponent_elo=old_p1, result=p2_result)
            return p1_obj.elo, p2_obj.elo, p1_obj.elo - old_p1, p2_obj.elo - old_p2

    @sync_to_async
    def _db_finalize(self, winner_id):
        DuelMatch.objects.filter(id=self.match_id).update(
            status='completed', winner_id=winner_id,
        )

    @sync_to_async
    def _maybe_abandon(self):
        DuelMatch.objects.filter(id=self.match_id, status='in_progress').update(
            status='abandoned',
        )

    @sync_to_async
    def _db_forfeit_round(self, round_number: int, player_num: int):
        from django.utils import timezone as tz
        now = tz.now()
        if player_num == 1:
            DuelRound.objects.filter(
                match_id=self.match_id,
                round_number=round_number,
                player1_submitted_at__isnull=True,
            ).update(
                player1_correct=False,
                player1_points=0,
                player1_snippets_used=0,
                player1_submitted_at=now,
            )
        else:
            DuelRound.objects.filter(
                match_id=self.match_id,
                round_number=round_number,
                player2_submitted_at__isnull=True,
            ).update(
                player2_correct=False,
                player2_points=0,
                player2_snippets_used=0,
                player2_submitted_at=now,
            )
