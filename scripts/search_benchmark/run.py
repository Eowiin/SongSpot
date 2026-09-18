"""Run via isolated compose runner; refuses non-benchmark databases."""
import os, sys, json, time, statistics
from pathlib import Path
sys.path.insert(0, '/workspace/songspot_backend')
os.environ.setdefault('DJANGO_SETTINGS_MODULE','songspot.settings')
import django
django.setup()
from django.conf import settings
from game.models import Artist, Track
from game.services import catalog
from game.services.matching import normalize_query
from django.core.management import call_command
import requests
assert settings.DATABASES['default']['NAME']=='search_test', 'Only isolated search_test database allowed'
root=Path('/workspace/docs/search')
corpus=json.loads((root/os.environ.get('CORPUS_FILE','corpus.json')).read_text())
prefix=os.environ.get('REPORT_PREFIX','')
for i in range(int(os.environ.get('EXTRA_DOCS','0'))):
    corpus['documents'].append(dict(id=str(1000000+i),title=f'Synthetic title {i}',artist=f'Synthetic musician {i%1000}',artist_id=str(1000000+i%1000),rank=500000))
build_times={}
call_command('migrate',verbosity=0)
Track.objects.all().delete()
Artist.objects.all().delete()
for d in corpus['documents']:
    Artist.objects.get_or_create(deezer_id=int(d['artist_id']),defaults={'name':d['artist'],'nb_fan':100000})
    Track.objects.create(deezer_id=int(d['id']),title=d['title'],artist=d['artist'],deezer_artist_id=int(d['artist_id']),rank=d['rank'],has_preview=True)

def measure(name, search):
    records=[]
    for q in corpus['queries']:
        start=time.perf_counter(); ids=search(q['query']); elapsed=(time.perf_counter()-start)*1000
        rank=next((i+1 for i,v in enumerate(ids) if v in q['expected']),None)
        records.append(dict(**q,rank=rank,ms=round(elapsed,3),passed=rank is not None and rank<=q['max_rank']))
    warm=[]
    for q in corpus['queries']:
        t=time.perf_counter();search(q['query']);warm.append((time.perf_counter()-t)*1000)
    report={'index_seconds':build_times.get(name), 'warm_p95_ms':sorted(warm)[int(len(warm)*.95)], 'warm_p99_ms':sorted(warm)[int(len(warm)*.99)], 'engine':name,'documents':len(corpus['documents']),'queries':len(records),'scope':corpus['provenance']+' Single client, first pass; not capacity/SLA evidence','results':records}
    for split in ['tuning','validation']:
        rows=[r for r in records if r['split']==split]
        if not rows:
            report[split]={}
            continue
        times=sorted(r['ms'] for r in rows)
        report[split]={'pass':sum(r['passed'] for r in rows),'count':len(rows),'recall20':sum(bool(r['rank'] and r['rank']<=20) for r in rows)/len(rows),'mrr':statistics.mean(1/r['rank'] if r['rank'] else 0 for r in rows),'p95_ms':times[int(len(times)*.95)],'p99_ms':times[min(len(times)-1,int(len(times)*.99))]}
    (root/(prefix+name+'.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(name, report['tuning'],report['validation'],flush=True)
    if name=='integrated-meili' and any(not r['passed'] for r in records):
        raise SystemExit('Integrated search acceptance failed; see report')

mode=sys.argv[1] if len(sys.argv)>1 else 'baseline'
if mode in ('audit','baseline'):
    import types
    legacy=types.ModuleType('game.services.baseline')
    legacy.__package__='game.services'
    exec(compile(Path('/baseline.py').read_text(),'/baseline.py','exec'),legacy.__dict__)
    catalog=legacy
if mode in ('baseline', 'postgres', 'audit'):
    measure('baseline' if mode in ('baseline','audit') else 'postgres-full-fields',lambda q:[str(t.deezer_id) for t in catalog._dedupe(catalog._candidates(catalog._query_filter(q),q),40,q)] if catalog._query_filter(q) else [])
elif mode=='integrated':
    from game.services.search_index import rebuild
    from game.services.search import search
    settings.SEARCH_BACKEND='meili'
    settings.SEARCH_ENRICHMENT_ENABLED=False
    rebuild()
    measure('integrated-meili',lambda q: [str(t.deezer_id) for t in search('tracks',q,enqueue=False)['rows']])
else:
    h={'X-TYPESENSE-API-KEY':'local-search-only'}; ts=os.environ['TYPESENSE_URL']; me=os.environ['MEILI_URL']; mh={'Authorization':'Bearer local-search-only'}
    docs=[dict(d,title=normalize_query(d['title']),artist=normalize_query(d['artist'])) for d in corpus['documents']]
    build_start=time.perf_counter()
    requests.delete(ts+'/collections/songs',headers=h,timeout=5)
    r=requests.post(ts+'/collections',headers=h,json={'name':'songs','fields':[{'name':'title','type':'string'},{'name':'artist','type':'string'},{'name':'rank','type':'int32'}],'default_sorting_field':'rank'},timeout=5);r.raise_for_status()
    r=requests.post(ts+'/collections/songs/documents/import?action=upsert',headers=h,data='\n'.join(json.dumps(d) for d in docs),timeout=30);r.raise_for_status();assert all(json.loads(l)['success'] for l in r.text.splitlines())
    build_times['typesense-29']=time.perf_counter()-build_start
    def task(r):
        r.raise_for_status(); uid=r.json()['taskUid']; deadline=time.monotonic()+60
        while time.monotonic()<deadline:
            status=requests.get(me+f'/tasks/{uid}',headers=mh,timeout=5).json()
            if status['status']=='succeeded':return
            if status['status']=='failed':raise RuntimeError(status)
            time.sleep(.05)
        raise TimeoutError('Meilisearch task')
    deleted=requests.delete(me+'/indexes/songs',headers=mh,timeout=5)
    if deleted.status_code != 404:task(deleted)
    build_start=time.perf_counter()
    task(requests.post(me+'/indexes/songs/documents?primaryKey=id',headers=mh,json=docs,timeout=30))
    task(requests.patch(me+'/indexes/songs/settings',headers=mh,json={'searchableAttributes':['title','artist'],'rankingRules':['words','typo','proximity','attribute','exactness','rank:desc']},timeout=5))
    build_times['meilisearch-1.15.2']=time.perf_counter()-build_start
    def typesense(q):
        r=requests.get(ts+'/collections/songs/documents/search',headers=h,params={'q':normalize_query(q),'query_by':'title,artist','per_page':40,'drop_tokens_threshold':0},timeout=5);r.raise_for_status();return [d['document']['id'] for d in r.json()['hits']]
    def meili(q):
        r=requests.post(me+'/indexes/songs/search',headers=mh,json={'q':normalize_query(q),'limit':40,'matchingStrategy':'all'},timeout=5);r.raise_for_status();return [d['id'] for d in r.json()['hits']]
    measure('typesense-29',typesense);measure('meilisearch-1.15.2',meili)
