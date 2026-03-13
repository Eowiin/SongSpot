from datetime import datetime, time, timedelta, timezone as dt_timezone

from django.conf import settings
from django.utils import timezone

from .models import (
    DAILY_MODE_CHOICES,
    DAILY_MODE_DECADE,
    DAILY_MODE_GENRE,
    DAILY_MODE_HARDCORE,
    DAILY_MODE_MIX,
    RoomDailyModeState,
)


DAILY_MODE_CONFIG = {
    DAILY_MODE_MIX: {
        'label': 'Daily Mix',
        'subtitle': 'Fully random song for everyone today',
        'cost_coins': 0,
        'free': True,
        'enabled': True,
    },
    DAILY_MODE_GENRE: {
        'label': 'Daily Genre',
        'subtitle': 'Same genre for everyone in the room today',
        'cost_coins': 120,
        'free': False,
        'enabled': True,
    },
    DAILY_MODE_DECADE: {
        'label': 'Daily Decade',
        'subtitle': 'Same decade for everyone in the room today',
        'cost_coins': 120,
        'free': False,
        'enabled': True,
    },
    DAILY_MODE_HARDCORE: {
        'label': 'Hardcore',
        'subtitle': 'Same daily song, but no hints and no retries',
        'cost_coins': 160,
        'free': False,
        'enabled': True,
    },
}


def active_game_date():
    """
    Returns the 'active' date for daily game content.
    The day rolls over at 12:00 UTC when the cron pre-generates new content.
    """
    now = timezone.now()
    if now.hour < 12:
        return (now - timedelta(days=1)).date()
    return now.date()


def active_game_window(active_date):
    """
    Returns the UTC datetime window for a given active game date.
    Active day D spans from D 12:00 UTC to D+1 12:00 UTC.
    """
    start = datetime.combine(active_date, time(hour=12, tzinfo=dt_timezone.utc))
    end = start + timedelta(days=1)
    return start, end


def supported_daily_modes():
    return {choice for choice, _label in DAILY_MODE_CHOICES}


def is_daily_mode_enabled(mode):
    config = DAILY_MODE_CONFIG.get(mode)
    return bool(config and config.get('enabled'))


def enabled_daily_modes():
    return [
        mode
        for mode, _label in DAILY_MODE_CHOICES
        if is_daily_mode_enabled(mode)
    ]


def daily_mode_cost(mode):
    return int(DAILY_MODE_CONFIG.get(mode, {}).get('cost_coins', 0))


def daily_mode_label(mode):
    return DAILY_MODE_CONFIG.get(mode, {}).get('label', mode.title())


def daily_mode_subtitle(mode):
    return DAILY_MODE_CONFIG.get(mode, {}).get('subtitle', '')


def is_daily_mode_free(mode):
    return bool(DAILY_MODE_CONFIG.get(mode, {}).get('free', False))


def is_room_daily_mode_unlocked(room, mode, active_date, *, state_map=None):
    if is_daily_mode_free(mode):
        return True
    if not is_daily_mode_enabled(mode):
        return False

    if state_map is None:
        state = (
            RoomDailyModeState.objects.filter(room=room, mode=mode).first()
        )
    else:
        state = state_map.get(mode)
    return bool(state and state.unlocked_for_date == active_date)


def is_daily_mode_accessible(room, mode, active_date, *, state_map=None):
    if mode not in supported_daily_modes():
        return False
    if is_daily_mode_free(mode):
        return True
    return is_room_daily_mode_unlocked(
        room,
        mode,
        active_date,
        state_map=state_map,
    )


def serialize_room_daily_modes(room, active_date):
    states = {
        state.mode: state
        for state in RoomDailyModeState.objects.filter(room=room).prefetch_related(
            'contributions'
        )
    }
    _window_start, unlocked_until = active_game_window(active_date)

    payload = []
    for mode in enabled_daily_modes():
        cost = daily_mode_cost(mode)
        is_free = is_daily_mode_free(mode)
        state = states.get(mode)
        unlocked = is_room_daily_mode_unlocked(
            room,
            mode,
            active_date,
            state_map=states,
        )
        if is_free:
            progress_coins = 0
            remaining_coins = 0
            contributor_count = 0
        elif unlocked:
            progress_coins = cost
            remaining_coins = 0
            contributor_count = state.last_unlock_contributor_count if state else 0
        else:
            progress_coins = state.progress_coins if state else 0
            remaining_coins = max(cost - progress_coins, 0)
            contributor_count = state.contributions.count() if state else 0

        payload.append(
            {
                'mode': mode,
                'label': daily_mode_label(mode),
                'subtitle': daily_mode_subtitle(mode),
                'cost_coins': cost,
                'is_free': is_free,
                'is_enabled': True,
                'is_unlocked': unlocked,
                'unlocked_until': unlocked_until.isoformat() if unlocked else None,
                'progress_coins': progress_coins,
                'remaining_coins': remaining_coins,
                'contributor_count': contributor_count,
            }
        )

    return payload
