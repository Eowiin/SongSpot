"""Versioned local search. No round state enters candidate generation."""
import logging
import time
from django.conf import settings
from ..models import Artist, Track, SearchEnrichment
from .matching import normalize_query
from .search_index import Index, IndexUnavailable
from .search_ranking import lexical_tier

logger = logging.getLogger(__name__)


def search(kind, query, limit=40, offset=0, enqueue=True):
    started = time.monotonic()
    from . import catalog, typos
    from .search_enrichment import schedule, status
    query = (query or '').strip()[:255]
    limit = max(1, min(int(limit), 40))
    offset = max(0, min(int(offset), 400))
    if len(normalize_query(query)) < 2:
        return dict(rows=[], next_offset=None, enrichment='idle', degraded=False)
    degraded = False
    hits = []
    total = 0
    if settings.SEARCH_BACKEND == 'meili':
        try:
            result = Index().request('POST', f'/indexes/songspot_{kind}/search', {
                'q': normalize_query(query), 'offset': 0, 'limit': 400,
                'matchingStrategy': 'all',
            })
            hits = result['hits']
            total = result.get('estimatedTotalHits', 0)
        except (IndexUnavailable, KeyError):
            degraded = True
            logger.warning('search_index_unavailable kind=%s', kind)
    ids = [h['id'] for h in hits]
    model = Track if kind == 'tracks' else Artist
    objects = {str(r.pk): r for r in model.objects.filter(pk__in=ids)}
    rows = [objects[x] for x in ids if x in objects]
    # Provider matches survive the short import -> index acknowledgement gap.
    # This also keeps a typo usable while the projection is unavailable.
    remembered = SearchEnrichment.objects.filter(kind=kind, norm_query=normalize_query(query)[:255]).values_list('track_ids', flat=True).first()
    if remembered:
        rows.extend(r for r in model.objects.filter(pk__in=remembered) if typos.resembles(
            query, r.title if kind == 'tracks' else '', r.artist if kind == 'tracks' else r.name))
    if kind == 'tracks':
        blocked = set(Artist.objects.filter(is_blocked=True).values_list('pk', flat=True))
        rows = [r for r in rows if r.deezer_artist_id not in blocked]
        # Complete local fields guarantee new playable rows remain findable
        # before the index worker catches up (including an index outage).
        matches = catalog._query_filter(query)
        local = catalog._candidates(matches, query) if matches else []
        rows = catalog._dedupe(rows+local, 400, query)
    else:
        rows = [r for r in rows if not r.is_blocked]
        local = catalog._local_artists(query, 400)
        unique = {str(r.pk) if r.pk else r.name: r for r in rows+local}
        rows = sorted(unique.values(), key=lambda r: (
            lexical_tier('', r.name, query), r.is_junk, -r.nb_fan, str(r.pk)))
    # Exact/full-token coverage is evidence of confidence; fuzzy/prefix-only
    # coverage warrants discovery. Freshness and retries live in durable state.
    confident = any(lexical_tier(r.title if kind=='tracks' else '',
                               r.artist if kind=='tracks' else r.name, query) <= 2 for r in rows)
    if enqueue and settings.SEARCH_ENRICHMENT_ENABLED and not confident:
        schedule(kind, query)
    logger.info('search_request kind=%s duration_ms=%.3f empty=%s degraded=%s',
                kind, (time.monotonic()-started)*1000, not bool(rows), degraded)
    return dict(rows=rows[offset:offset+limit], next_offset=offset+limit if offset+limit < min(len(rows),400) else None,
                refine_required=total>400,
                enrichment=status(kind, query), degraded=degraded)
