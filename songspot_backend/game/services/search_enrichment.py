"""Durable deduplicated jobs. Provider failures are never negative results."""
import logging
import uuid
from datetime import timedelta
from django.db import transaction
from django.db.models import Q, Case, When, Value, IntegerField
from django.utils import timezone
from ..models import SearchEnrichment
from .matching import normalize_query
from .deezer_http import DeezerHttp, DeezerUnavailable

logger = logging.getLogger(__name__)

POSITIVE_TTL = timedelta(days=7)
EMPTY_TTL = timedelta(hours=6)
LEASE = timedelta(seconds=60)
MAX_ATTEMPTS = 8


def schedule(kind, query):
    norm = normalize_query(query)[:255]
    if not norm:
        return
    now = timezone.now()
    with transaction.atomic():
        row, _ = SearchEnrichment.objects.select_for_update().get_or_create(
            kind=kind, norm_query=norm, defaults={'enriched_at': now, 'query': query[:255],
            'state': 'pending', 'next_attempt_at': now})
        if row.state == 'legacy':
            # Old claims prove nothing. Stagger only queries requested again.
            import hashlib
            delay = int(hashlib.sha256(norm.encode()).hexdigest()[:8], 16) % 300
            row.state = 'pending'; row.next_attempt_at = now+timedelta(seconds=delay)
        elif row.state not in ('pending', 'running') and (row.next_attempt_at is None or row.next_attempt_at <= now):
            row.state = 'pending'; row.next_attempt_at = now
            row.attempts = 0
        row.query = query[:255]
        row.save(update_fields=['state','next_attempt_at','query','attempts'])


def status(kind, query):
    row = SearchEnrichment.objects.filter(kind=kind, norm_query=normalize_query(query)[:255]).first()
    return row.state if row and row.state != 'legacy' else 'idle'


def claim():
    now = timezone.now()
    with transaction.atomic():
        row = SearchEnrichment.objects.select_for_update(skip_locked=True).filter(
            Q(state__in=['pending','failed'], next_attempt_at__lte=now)
            | Q(state='running', lease_until__lte=now)
        ).annotate(queue_priority=Case(
            When(state='pending', then=Value(0)), When(state='running', then=Value(1)),
            default=Value(2), output_field=IntegerField(),
        )).order_by('queue_priority','next_attempt_at','pk').first()
        if not row:
            return None
        row.state = 'running'; row.lease_until = now+LEASE; row.lease_token = uuid.uuid4()
        row.attempts += 1
        row.save(update_fields=['state','lease_until','lease_token','attempts'])
        return row


def run_one():
    from . import catalog, typos
    row = claim()
    if not row:
        return False
    state, error, ids = 'failed', '', []
    try:
        # Direct transport preserves failures; legacy list wrappers do not.
        path = '/search' if row.kind == 'tracks' else '/search/artist'
        payload = DeezerHttp(max_wait=4, priority='search' if row.attempts == 1 else 'background').get(path, {'q': row.query or row.norm_query, 'limit': 50}, allow_stale=False)
        if not isinstance(payload, dict) or not isinstance(payload.get('data'), list):
            raise DeezerUnavailable('invalid payload')
        if row.kind == 'tracks':
            rows = catalog.upsert_tracks(payload['data'])
            ids = [str(t.pk) for t in rows if typos.resembles(row.query or row.norm_query, t.title, t.artist)]
        else:
            rows = [catalog.upsert_artist(p) for p in payload['data']]
            ids = [str(a.pk) for a in rows if a and typos.resembles(row.query or row.norm_query, '', a.name)]
        if payload['data'] and not any(rows):
            raise DeezerUnavailable('unusable payload')
        state = 'succeeded' if payload['data'] else 'empty'
    except Exception as exc:
        error = type(exc).__name__[:64]
    now = timezone.now()
    ttl = POSITIVE_TTL if state == 'succeeded' else EMPTY_TTL if state == 'empty' else timedelta(seconds=min(300, 2**min(row.attempts,8)))
    SearchEnrichment.objects.filter(pk=row.pk, lease_token=row.lease_token, state='running').update(
        state=state, enriched_at=now, next_attempt_at=None if state == 'failed' and row.attempts >= MAX_ATTEMPTS else now+ttl,
        lease_until=None, lease_token=None, last_error=error, track_ids=ids)
    logger.info('search_enrichment kind=%s state=%s error=%s attempts=%s', row.kind, state, error, row.attempts)
    return True
