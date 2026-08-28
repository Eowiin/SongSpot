"""Context shared by every page rendered from templates/site/.

Registered globally (see TEMPLATES in settings.py) so that views outside this
module — the password reset page in authentication/views.py, for instance —
also get the header, footer and store links without repeating themselves.
"""
import os

from game.models import CATEGORY_CHOICES

SUPPORT_EMAIL = os.environ.get('SUPPORT_EMAIL', 'eowin.dev@gmail.com')

# The browser build is served from the same origin as the API (see
# docs/WEB_DEPLOYMENT.md), which is what lets the web client skip CORS and
# WebSocket origin configuration entirely.
PLAY_URL = os.environ.get('WEB_APP_URL', '/play/')

PLAY_STORE_URL = os.environ.get(
    'PLAY_STORE_URL',
    'https://play.google.com/store/apps/details?id=com.songspot.app',
)

# No default: an App Store link needs the numeric Apple ID, and the button is
# hidden rather than pointing somewhere wrong.
APP_STORE_URL = os.environ.get('APP_STORE_URL', '')

GENRES = [label for _, label in CATEGORY_CHOICES]

# Fixed so the markup is identical on every request — the bars are decoration,
# and a stable page caches better than a randomised one.
_BAR_HEIGHTS = (
    38, 62, 45, 88, 54, 71, 96, 42, 66, 80, 35, 58, 92, 49,
    74, 40, 85, 63, 51, 78, 44, 68, 95, 39, 60, 83, 47, 70,
)

WAVEFORM = [
    {'h': height, 'd': (index * 70) % 900}
    for index, height in enumerate(_BAR_HEIGHTS)
]


def site(request):
    return {
        'play_url': PLAY_URL,
        'support_email': SUPPORT_EMAIL,
        'play_store_url': PLAY_STORE_URL,
        'app_store_url': APP_STORE_URL,
        'genres': GENRES,
        'genre_count': len(GENRES),
        'waveform': WAVEFORM,
    }
