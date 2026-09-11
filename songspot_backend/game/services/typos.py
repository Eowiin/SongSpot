"""
Whether a Deezer search result resembles what the player typed.

Deezer's search forgives typos and missing spaces that ours does not: it finds
Bad Bunny for `bad buny` and Stray Kids for `straykids`. When the catalogue has
no answer at all, its results are shown instead of an empty list (see
`catalog.search_tracks`). But Deezer always returns something, and for a query
it cannot place that something is unrelated: `gina and georgia` brings back
"Gina And Elvira's Theme" by Giorgio Moroder. Showing that would be worse than
showing nothing, so each result must pass this check first.

A result resembles the query when every word of the query matches a word of
the title or the artist, in one of these ways:

* with a few mistakes, allowed according to the word's length: none up to 3
  letters, one up to 7, two beyond. Two letters swapped count as one mistake,
  since `nigth` and `jucie` are how people mistype;
* as consecutive words typed without spaces: `straykids`, `karolg`, or `intro`
  for a title spelled out as "I N T R O";
* for the last word only, as the start of a word, because the player may still
  be typing it (`oliva rodr`).

A word of one or two letters is allowed to match nothing, as long as the longer
words all do: `la cancion con yandel` names "CANCIÓN CON YANDEL".

Tuned on the 70 most frequent searches that still came back empty on prod in
September 2026 after the short-word fix, which were mostly typos.
"""

from game.services.matching import normalize_query

# Words up to this long may go unmatched when the longer words all match.
SHORT_WORD = 2


def resembles(query: str, title: str, artist: str) -> bool:
    """True if `query` names this title and artist, allowing for typos."""
    typed = normalize_query(query).split()
    words = normalize_query(f'{title} {artist}').split()
    if not typed or not words:
        return False
    has_long_word = any(len(token) > SHORT_WORD for token in typed)
    last = len(typed) - 1
    for position, token in enumerate(typed):
        if _fits(token, words, partial=(position == last)):
            continue
        if len(token) <= SHORT_WORD and has_long_word:
            continue
        return False
    return True


def _fits(token: str, words: list[str], partial: bool) -> bool:
    budget = _mistakes_allowed(len(token))
    for start in range(len(words)):
        run = ''
        for word in words[start:]:
            run += word
            if _within(token, run, budget):
                return True
            if partial and len(run) > len(token) and _within(token, run[:len(token)], budget):
                return True
            if len(run) > len(token) + budget:
                break
    return False


def _mistakes_allowed(length: int) -> int:
    if length <= 3:
        return 0
    if length <= 7:
        return 1
    return 2


def _within(a: str, b: str, budget: int) -> bool:
    """
    True if `a` becomes `b` in at most `budget` edits.

    An edit is an insertion, a deletion, a substitution, or two neighbouring
    letters swapped.
    """
    if abs(len(a) - len(b)) > budget:
        return False
    if budget == 0:
        return a == b
    before_previous: list[int] = []
    previous = list(range(len(b) + 1))
    for i in range(1, len(a) + 1):
        current = [i] + [0] * len(b)
        for j in range(1, len(b) + 1):
            current[j] = min(
                previous[j] + 1,
                current[j - 1] + 1,
                previous[j - 1] + (a[i - 1] != b[j - 1]),
            )
            if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
                current[j] = min(current[j], before_previous[j - 2] + 1)
        # A swap reaches back two rows, so only two rows over budget prove
        # nothing later can come back under it.
        if min(current) > budget and min(previous) > budget:
            return False
        before_previous, previous = previous, current
    return previous[-1] <= budget
