"""Search normalization is deliberately separate from answer identity."""
from .matching import normalize_query


def group_key(track):
    # Remixes/parenthetical songs are distinct. Unknown identities stay separate.
    return (normalize_query(track.title), str(track.deezer_artist_id or track.pk))


def lexical_tier(title, artist, query):
    q = normalize_query(query)
    title, artist = normalize_query(title), normalize_query(artist)
    if q in (title, artist):
        return 0
    if q == title.removeprefix('the '):
        return 1
    tokens = q.split()
    words = (title+' '+artist).split()
    if all(t in words for t in tokens):
        return 2
    if title.startswith(q) or artist.startswith(q):
        return 3
    if all(any(w.startswith(t) for w in words) for t in tokens):
        return 4
    if q.replace(' ', '') in (title.replace(' ', ''), artist.replace(' ', '')):
        return 4
    return 5


def rank_key(track, query, artists=None):
    artist = (artists or {}).get(track.deezer_artist_id)
    tier = lexical_tier(track.title, track.artist, query)
    if artist:
        tier = min(tier, lexical_tier(track.title, artist.name, query))
    return (tier,
            bool(artist and artist.is_junk), -track.rank,
            -(artist.nb_fan if artist else 0), str(track.pk))
