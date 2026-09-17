"""Rebuildable Meilisearch projection. PostgreSQL is always authoritative."""
import hashlib
import time
import uuid
from contextlib import contextmanager

import requests
from django.conf import settings
from django.db import connection, transaction
from django.db.models import Q
from ..models import Artist, Track, SearchOutbox
from .matching import normalize_query
from .search_ranking import group_key


class IndexUnavailable(Exception):
    pass


class Index:
    def __init__(self):
        self.url = settings.MEILI_URL.rstrip('/')
        self.session = requests.Session()
        self.session.headers['Authorization'] = 'Bearer '+settings.MEILI_KEY

    def request(self, method, path, payload=None, wait=False):
        try:
            response = self.session.request(method, self.url+path, json=payload, timeout=(.5, 2))
            response.raise_for_status()
            result = response.json()
            if wait:
                deadline = time.monotonic()+60
                while time.monotonic() < deadline:
                    task = self.request('GET', '/tasks/'+str(result['taskUid']))
                    if task['status'] == 'succeeded':
                        return task
                    if task['status'] == 'failed':
                        raise IndexUnavailable(str(task.get('error', {}).get('code')))
                    time.sleep(.05)
                raise IndexUnavailable('index task timed out')
            return result
        except (requests.RequestException, ValueError, KeyError) as exc:
            raise IndexUnavailable('index unavailable') from exc

    def configure(self, name):
        self.request('POST', '/indexes', {'uid': name, 'primaryKey': 'id'}, wait=True)
        self.request('PATCH', f'/indexes/{name}/settings', {
            'searchableAttributes': ['title', 'artist', 'aliases'],
            'rankingRules': ['words', 'typo', 'proximity', 'attribute', 'exactness', 'rank:desc'],
            'distinctAttribute': 'group',
            'pagination': {'maxTotalHits': 10000},
        }, wait=True)

    def put(self, name, docs):
        if docs:
            self.request('POST', f'/indexes/{name}/documents', docs, wait=True)

    def delete(self, name, ids):
        if ids:
            self.request('POST', f'/indexes/{name}/documents/delete-batch', ids, wait=True)


def document(kind, row, blocked=None, artist_names=None):
    if kind == 'artists':
        if row.is_blocked:
            return None
        title, artist = '', normalize_query(row.name)
        group = str(row.pk)
        rank = row.nb_fan
    else:
        if (row.deezer_artist_id in blocked if blocked is not None else
                Artist.objects.filter(pk=row.deezer_artist_id, is_blocked=True).exists()):
            return None
        title, artist = normalize_query(row.title), normalize_query(row.artist)
        group = hashlib.sha256(repr(group_key(row)).encode()).hexdigest()
        rank = row.rank
    aliases = [title.replace(' ', ''), artist.replace(' ', ''), artist.removeprefix('the ')]
    if kind == 'tracks':
        aliases.extend(normalize_query(c.get('name', '')) for c in row.contributors if isinstance(c, dict))
        aliases.append(normalize_query((artist_names or {}).get(row.deezer_artist_id, '')))
    return dict(id=str(row.pk), title=title, artist=artist, group=group, rank=rank, aliases=aliases)


def documents(kind, rows):
    rows = list(rows)
    if kind == 'tracks':
        artists = list(Artist.objects.filter(pk__in={r.deezer_artist_id for r in rows}).values('pk','name','is_blocked'))
        blocked = {a['pk'] for a in artists if a['is_blocked']}
        names = {a['pk']: a['name'] for a in artists}
    else:
        blocked, names = set(), {}
    return [d for r in rows if (d := document(kind, r, blocked, names)) is not None]


@contextmanager
def consumer_lock():
    if connection.vendor != 'postgresql':
        raise RuntimeError('Search indexing requires PostgreSQL')
    with connection.cursor() as cursor:
        cursor.execute('SELECT pg_try_advisory_lock(73920146)')
        if not cursor.fetchone()[0]:
            raise RuntimeError('Another index worker/rebuild is running')
    try:
        yield
    finally:
        with connection.cursor() as cursor:
            cursor.execute('SELECT pg_advisory_unlock(73920146)')


def drain(index, names=None, batches=1):
    names = names or {'tracks': 'songspot_tracks', 'artists': 'songspot_artists'}
    total = 0
    for _ in range(batches):
        # No advancing sequence watermark: a lower ID can commit later.
        # Delete only acknowledged rows. Replays fetch current state, never old payloads.
        with transaction.atomic():
            events = list(SearchOutbox.objects.select_for_update().order_by('id')[:200])
            if not events:
                break
            changed = {'tracks': set(), 'artists': set()}
            for event in events:
                changed[event.kind].add(event.entity_id)
            for kind, model in [('artists', Artist), ('tracks', Track)]:
                explicit = changed[kind]
                selected = Q(pk__in=explicit)
                if kind == 'tracks':
                    selected |= Q(deezer_artist_id__in=changed['artists'])
                missing = set(explicit)
                batch = []

                def flush(rows):
                    docs = documents(kind, rows)
                    index.put(names[kind], docs)
                    index.delete(names[kind], sorted({str(r.pk) for r in rows}-{d['id'] for d in docs}))

                for row in model.objects.filter(selected).order_by('pk').iterator(chunk_size=500):
                    missing.discard(str(row.pk))
                    batch.append(row)
                    if len(batch) == 500:
                        flush(batch); batch = []
                flush(batch)
                index.delete(names[kind], sorted(missing))
            SearchOutbox.objects.filter(pk__in=[e.pk for e in events]).delete()
            total += len(events)
    return total


def rebuild():
    index = Index()
    suffix = uuid.uuid4().hex[:12]
    names = {kind: 'songspot_'+kind+'_'+suffix for kind in ('tracks','artists')}
    with consumer_lock():
        # Keep outbox until after swap: a failed build must not steal changes
        # from the still-active index. A DB rollback causes harmless replays.
        with transaction.atomic():
            for kind, model in [('artists', Artist), ('tracks', Track)]:
                index.configure(names[kind])
                batch = []
                for row in model.objects.order_by('pk').iterator(chunk_size=500):
                    batch.append(row)
                    if len(batch) == 500:
                        index.put(names[kind], documents(kind, batch)); batch = []
                index.put(names[kind], documents(kind, batch))
            while drain(index, names=names):
                pass
            blocked_ids = Artist.objects.filter(is_blocked=True).values('pk')
            expected = {'tracks': Track.objects.exclude(deezer_artist_id__in=blocked_ids).count(),
                        'artists': Artist.objects.filter(is_blocked=False).count()}
            for kind, name in names.items():
                stats = index.request('GET', '/indexes/'+name+'/stats')
                if stats['isIndexing'] or stats['numberOfDocuments'] != expected[kind]:
                    raise IndexUnavailable('Projection incomplete; source may have changed, retry rebuild')
            # Bootstrap empty live names, then atomically swap both collections.
            for kind in names:
                live = 'songspot_'+kind
                try:
                    index.request('GET', '/indexes/'+live)
                except IndexUnavailable:
                    index.configure(live)
            index.request('POST', '/swap-indexes', [
                {'indexes': ['songspot_'+kind, name]} for kind,name in names.items()
            ], wait=True)
    return names  # These names now contain the previous index; retain for rollback.
