"""
Song identity — how the game decides that two Deezer rows are the same song.

Deezer has no notion of "the song"; it has releases. `Blinding Lights` alone
exists as the *After Hours* album cut, the single, a live recording and three
remixes, each with its own track ID:

    908604612   Blinding Lights                       (After Hours)
    1161752782  Blinding Lights (Remix)
    2166259437  Blinding Lights (Live)                (Live At SoFi Stadium)
    1078622722  Blinding Lights (Major Lazer Remix)

The game used to compare local UUIDs, which worked only because the catalogue
was a closed list with one row per song. Against the open catalogue that rule
marks a player wrong for naming the right song off the wrong release — the
single worst thing a guessing game can do. So identity is a *normalised* pair
(title, artist) instead, and the comparison lives here so the solo endpoint,
the duel consumer and the catalogue importer all judge answers identically.

Normalisation is lenient about *releases* and strict about *artists*.
Everything that only names an edition — the parenthetical qualifiers, the
featured guests, the dash suffixes — is thrown away before comparing, so any
pressing of the song counts. The artist still has to match, because the guess
list prints the artist on every row: picking a cover by someone else is
choosing a different recording, not fumbling the same one.
"""

import re
import unicodedata
from typing import Optional

# Qualifiers that describe a release rather than the song. Used both to strip
# dash-suffixes during normalisation and to spot variants worth keeping out of
# the *played* pool (a live cut makes for a poor snippet even though it is a
# perfectly valid answer).
_VARIANT_WORDS = (
    r'remaster(?:ed)?'
    r'|live(?:\s+(?:at|from|version|recording|session))?'
    r'|acoustic(?:\s+version)?'
    r'|demo(?:\s+version)?'
    r'|instrumental(?:\s+version)?'
    r'|karaoke'
    r'|cover(?:\s+version)?'
    r'|tribute'
    r'|radio\s+edit'
    r'|single\s+(?:version|edit)'
    r'|album\s+version'
    r'|original\s+mix'
    r'|extended(?:\s+(?:mix|version))?'
    r'|club\s+mix'
    r'|remix'
    r'|edit'
    r'|anniversary\s+edition'
    r'|deluxe(?:\s+edition)?'
    r'|bonus\s+track'
    r'|mono(?:\s+version)?'
    r'|sped\s+up'
    r'|slowed'
    r'|nightcore'
    r'|version'
)

# "(2011 Remaster)", "[Live at Wembley]", "(Acoustic Version)" — and, just as
# often, "(Major Lazer Remix)" or "(Eran Hersh & Shooma Remix)", where the
# keyword trails the remixer's name. Anything up to the closing bracket may
# precede it, but the `\b` guards mean a keyword only counts as a whole word:
# "Delivery" does not contain "live", and "Believe" does not either.
_VARIANT_PAREN_RE = re.compile(
    r'[\(\[][^\)\]]{0,60}?\b(?:' + _VARIANT_WORDS + r')\b',
    re.IGNORECASE,
)

# "Song Title - Live", "Song Title – 2011 Remaster"
_VARIANT_SUFFIX_RE = re.compile(
    r'\s+[-–—]\s+(?:\d{4}\s+)?(?:' + _VARIANT_WORDS + r')\b.*$',
    re.IGNORECASE,
)

# Featured guests, parenthesised or not: "(feat. X)", "ft. X", "avec X".
_FEAT_RE = re.compile(
    r'\s*[\(\[]?\s*\b(?:feat|feats|ft|featuring|avec|with|w/)\b\.?\s+[^\)\]]*[\)\]]?',
    re.IGNORECASE,
)

# Any remaining bracketed run. Stripped wholesale: on a guessing game the
# parenthetical is nearly always the release qualifier, and the rare title that
# genuinely carries one ("(I Can't Get No) Satisfaction") still normalises to
# something a player would recognise as that song.
_BRACKETS_RE = re.compile(r'[\(\[\{][^\)\]\}]*[\)\]\}]?')

_PUNCT_RE = re.compile(r"[^\w\s]", re.UNICODE)
_SPACE_RE = re.compile(r'\s+')

# Artist entities that exist only to re-record other people's songs. Excluded
# from *undirected* picks; a player who deliberately selects one can still play
# it, so this never gates the artist search itself.
_JUNK_ARTIST_RE = re.compile(
    r'\b(?:karaoke|tribute|cover(?:s|band)?|made\s+famous\s+by'
    r'|in\s+the\s+style\s+of|backing\s+track|instrumental\s+version'
    r'|nightcore|sped\s+up|8\s*bit|lullaby\s+versions?)\b',
    re.IGNORECASE,
)


def strip_accents(value: str) -> str:
    """`Beyoncé` → `Beyonce`, so an accent never costs a point."""
    decomposed = unicodedata.normalize('NFKD', value)
    return ''.join(c for c in decomposed if not unicodedata.combining(c))


def _collapse(value: str) -> str:
    value = strip_accents(value).lower()
    value = value.replace('&', ' and ')
    value = _PUNCT_RE.sub(' ', value)
    return _SPACE_RE.sub(' ', value).strip()


def normalize_title(title: Optional[str]) -> str:
    """
    Reduce a release title to the song it names.

    `Blinding Lights (Major Lazer Remix)`, `Blinding Lights - Live` and
    `Blinding Lights (feat. Someone)` all collapse to `blinding lights`.
    """
    if not title:
        return ''

    working = _VARIANT_SUFFIX_RE.sub('', title)
    working = _FEAT_RE.sub(' ', working)
    working = _BRACKETS_RE.sub(' ', working)

    collapsed = _collapse(working)
    # A title that is *only* a qualifier ("(Reprise)") would vanish entirely;
    # fall back to the plain form rather than return an empty key that would
    # match every other emptied title.
    return collapsed or _collapse(title)


def normalize_artist(artist: Optional[str]) -> str:
    """
    Reduce an artist credit to the act.

    Featured guests are dropped, `&` reads as `and`, and a leading `The` is
    ignored so `The Weeknd` and `Weeknd` are the same act. Collaborations are
    *not* split on `&` or `,` — that would turn `Simon & Garfunkel` into
    `Simon` and `Tyler, The Creator` into `Tyler`.
    """
    if not artist:
        return ''

    working = _FEAT_RE.sub(' ', artist)
    collapsed = _collapse(working)
    if collapsed.startswith('the '):
        collapsed = collapsed[4:]
    return collapsed or _collapse(artist)


def normalize_query(query: Optional[str]) -> str:
    """
    Fold a search box query the way stored titles and artists are folded.

    The guess list is matched against `norm_title`/`norm_artist`, which are
    accent-free and lower case. A query has to go through the same folding or
    it can never match them: `ROSALÍA` is stored as `rosalia`, so a player
    typing `rosalia` — or `Rosalía`, which SQLite's LIKE does not case-fold
    past ASCII — otherwise finds nothing.

    Unlike `normalize_title` this keeps release qualifiers: someone typing
    `live` is searching, not naming a song, and the words are still worth
    matching on.
    """
    return _collapse(query or '')


def is_variant_title(title: str) -> bool:
    """True for remasters, live cuts, remixes and the like."""
    if not title:
        return False
    return bool(_VARIANT_PAREN_RE.search(title) or _VARIANT_SUFFIX_RE.search(title))


def is_junk_artist(name: str) -> bool:
    """True for karaoke, tribute and cover acts."""
    if not name:
        return False
    return bool(_JUNK_ARTIST_RE.search(name))


def answer_matches(
    *,
    answer_deezer_id: Optional[int],
    answer_norm_title: str,
    answer_norm_artist: str,
    answer_artist_deezer_id: Optional[int],
    guess_deezer_id: Optional[int],
    guess_norm_title: str,
    guess_norm_artist: str,
    guess_artist_deezer_id: Optional[int],
) -> bool:
    """
    Decide whether a guess names the song being played.

    Three ways to be right, in cost order:
      1. the exact same Deezer track;
      2. the same normalised (title, artist) — the release-agnostic identity;
      3. the same normalised title by the same Deezer *artist entity*, which
         covers acts whose name Deezer spells inconsistently across releases.
    """
    if answer_deezer_id and guess_deezer_id and answer_deezer_id == guess_deezer_id:
        return True

    if not answer_norm_title or not guess_norm_title:
        return False

    if answer_norm_title != guess_norm_title:
        return False

    if answer_norm_artist and answer_norm_artist == guess_norm_artist:
        return True

    return bool(
        answer_artist_deezer_id
        and guess_artist_deezer_id
        and answer_artist_deezer_id == guess_artist_deezer_id
    )


def song_key(title: Optional[str], artist: Optional[str]) -> tuple[str, str]:
    """The dedup key used to show one row per song in search results."""
    return normalize_title(title), normalize_artist(artist)
