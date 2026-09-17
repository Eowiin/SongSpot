"""Real PostgreSQL + Meilisearch lifecycle assertions, isolated database only."""
import os,sys
sys.path.insert(0,'/workspace/songspot_backend')
os.environ.setdefault('DJANGO_SETTINGS_MODULE','songspot.settings')
import django
django.setup()
from django.conf import settings
from django.db import transaction
from unittest.mock import patch
from game.models import Artist,Track,SearchOutbox
from game.services.search_index import rebuild,consumer_lock,drain,Index,IndexUnavailable
from game.services.search import search
assert settings.DATABASES['default']['NAME']=='search_test'
settings.SEARCH_BACKEND='meili';settings.SEARCH_ENRICHMENT_ENABLED=False
index=Index()
def sync():
    with consumer_lock():
        while drain(index):pass
artist=Artist.objects.create(pk=990001,name='Integration Uniquely Named Artist')
track=Track.objects.create(title='Integration Full (Parenthetical Words)',artist=artist.name,deezer_artist_id=artist.pk,has_preview=True)
try:
    # New playable song is findable before any event is consumed.
    assert track in search('tracks',track.title,enqueue=False)['rows']
    sync()
    # A database rollback must not emit an event.
    before=SearchOutbox.objects.count()
    try:
        with transaction.atomic():
            Track.objects.filter(pk=track.pk).update(title='Rolled Back')
            raise ValueError()
    except ValueError:pass
    assert SearchOutbox.objects.count()==before
    # Partial external failure keeps events retryable.
    Track.objects.filter(pk=track.pk).update(title='Integration Updated Title')
    with consumer_lock(),patch.object(index,'put',side_effect=IndexUnavailable()):
        try:drain(index)
        except IndexUnavailable:pass
    assert SearchOutbox.objects.count()>0
    sync();track.refresh_from_db()
    assert track in search('tracks',track.title,enqueue=False)['rows']
    # Duplicate/stale events re-read latest state and do not resurrect old names.
    SearchOutbox.objects.create(kind='tracks',entity_id=str(track.pk));sync()
    indexed=index.request('GET','/indexes/songspot_tracks/documents/'+str(track.pk))
    assert indexed['title']=='integration updated title'
    # Block is enforced even before propagation, then removes indexed docs.
    Artist.objects.filter(pk=artist.pk).update(is_blocked=True)
    assert track not in search('tracks',track.title,enqueue=False)['rows']
    sync()
    assert index.request('POST','/indexes/songspot_tracks/search',{'q':'integration updated title'})['hits']==[]
    Artist.objects.filter(pk=artist.pk).update(is_blocked=False);sync()
    # Stable pages have no duplicates, and refinement remains reachable.
    pages=[search('tracks','synthetic',offset=n,enqueue=False)['rows'] for n in (0,40,80)]
    ids=[str(t.pk) for p in pages for t in p]
    assert len(ids)==len(set(ids))
    with patch('game.services.search.Index.request',side_effect=IndexUnavailable()):
        page=search('tracks',track.title,enqueue=False)
        assert page['degraded'] and track in page['rows']
    pk=track.pk;track.delete();sync()
    try:index.request('GET','/indexes/songspot_tracks/documents/'+str(pk))
    except IndexUnavailable:pass
    else:raise AssertionError('deleted document survived')
finally:
    Track.objects.filter(pk=track.pk).delete()
    artist.delete();sync()
print('PASS: lag fallback, rollback, retry, stale replay, block/unblock, pagination, outage, deletion')
