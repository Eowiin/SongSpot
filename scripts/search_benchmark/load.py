"""Local synthetic load and reconstruction probe; no provider traffic."""
import os, sys, json, time, statistics
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
sys.path.insert(0,'/workspace/songspot_backend')
os.environ.setdefault('DJANGO_SETTINGS_MODULE','songspot.settings')
import django
django.setup()
from django.conf import settings
from django.db import close_old_connections
from game.models import Track
from game.services.search import search
from game.services.search_index import rebuild
assert settings.DATABASES['default']['NAME']=='search_test'
settings.SEARCH_BACKEND='meili'; settings.SEARCH_ENRICHMENT_ENABLED=True
root=Path('/workspace/docs/search');corpus=json.loads((root/'corpus.json').read_text())
for start in range(0,25000,500):
    Track.objects.bulk_create([Track(title=f'Synthetic title {i}',artist=f'Synthetic musician {i%1000}',deezer_id=1000000+i,rank=500000) for i in range(start,start+500)],ignore_conflicts=True)
start=time.perf_counter();previous=rebuild();build=time.perf_counter()-start
qs=[q['query'] for q in corpus['queries']]
def run(q):
    close_old_connections()
    try:
        t=time.perf_counter();search('tracks',q);return (time.perf_counter()-t)*1000
    finally:close_old_connections()
first=run(qs[0]); warm=[run(q) for q in qs]
start=time.perf_counter()
with ThreadPoolExecutor(max_workers=8) as pool: times=list(pool.map(run,qs*3))
elapsed=time.perf_counter()-start
percentile=lambda vals,p: sorted(vals)[min(len(vals)-1,int(len(vals)*p))]
report=dict(enrichment_enqueue=True, enrichment_worker_running=False,scope='25282 synthetic tracks, 8 closed-loop clients; new connection per request; no real production catalogue, no OS cache eviction', tracks=Track.objects.count(),rebuild_seconds=build,previous_indexes=previous,first_request_ms=first,warm_p95_ms=percentile(warm,.95),warm_p99_ms=percentile(warm,.99),requests=len(times),concurrency=8,throughput_per_second=len(times)/elapsed,p50_ms=statistics.median(times),p95_ms=percentile(times,.95),p99_ms=percentile(times,.99))
(root/'load.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report),flush=True)
