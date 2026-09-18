"""Synthetic scale test. Never load a production environment or run remotely."""
import argparse
import json
import os
import random
import statistics
import sys
import time
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, '/workspace/songspot_backend')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'songspot.settings')
import django
django.setup()
from django.conf import settings
from django.core.management import call_command
from django.db import connection, connections, DatabaseError
from game.models import Artist, Track, SearchOutbox, SearchEnrichment
from game.services.search import search
from game.services.matching import normalize_query, normalize_artist, normalize_title

assert settings.DATABASES['default']['NAME'] == 'search_test'
assert settings.DATABASES['default']['HOST'] == 'db'
assert settings.SEARCH_BACKEND == 'postgres'
ROOT = Path('/workspace/docs/search')
CORPUS = json.loads((ROOT/'corpus.json').read_text())
REAL = json.loads((ROOT/'local-real-corpus.json').read_text())
OFFSET = 1_000_000_000


def seed(target, artists, reset=False):
    call_command('migrate', verbosity=0)
    if reset:
        with connection.cursor() as c:
            c.execute('TRUNCATE tracks, artists, search_outbox, search_enrichments CASCADE')
            c.execute('DROP TABLE IF EXISTS scale_state')
    if not Track.objects.exists():
        for corpus, offset in [(CORPUS, 0), (REAL, 20_000_000)]:
            people = {int(d['artist_id'])+offset: d['artist'] for d in corpus['documents']}
            Artist.objects.bulk_create([Artist(deezer_id=i, name=n, norm_name=normalize_artist(n), nb_fan=100000) for i,n in people.items()], ignore_conflicts=True)
            for start in range(0, len(corpus['documents']), 500):
                Track.objects.bulk_create([Track(deezer_id=int(d['id'])+offset, title=d['title'], artist=d['artist'], deezer_artist_id=int(d['artist_id'])+offset, rank=d['rank'], has_preview=True, norm_title=normalize_title(d['title']), norm_artist=normalize_artist(d['artist'])) for d in corpus['documents'][start:start+500]])
    # Snapshot fixture construction only: omit projection events, which are not
    # part of the measured read workload. Normalization trigger stays active.
    with connection.cursor() as c:
        c.execute('ALTER TABLE tracks DISABLE TRIGGER search_track_event')
        c.execute('ALTER TABLE artists DISABLE TRIGGER search_artist_event')
    try:
        vocabulary = sorted({w for d in REAL['documents'] for w in normalize_query(d['title']).split() if len(w)>=3})
        with connection.cursor() as c:
            c.execute('CREATE TABLE IF NOT EXISTS scale_words (id integer PRIMARY KEY, word text NOT NULL)')
            if not Artist.objects.filter(pk__gte=OFFSET).exists():
                c.executemany('INSERT INTO scale_words VALUES (%s,%s) ON CONFLICT DO NOTHING', list(enumerate(vocabulary,1)))
                c.execute('CREATE TABLE IF NOT EXISTS scale_state (id integer PRIMARY KEY, generated integer)')
                c.execute('INSERT INTO scale_state VALUES (1,0) ON CONFLICT DO NOTHING')
                remaining = artists-Artist.objects.count()
                for start in range(0, remaining, 50000):
                    c.execute('''INSERT INTO artists (deezer_id,name,norm_name,nb_fan,is_junk,is_blocked,created_at)
                        SELECT %s+g, a.word||' '||b.word||' '||g, a.word||' '||b.word||' '||g,
                        (g*7919)%%1000000, g%%100=0, g%%1000=0, now()
                        FROM generate_series(%s::bigint,%s::bigint) g
                        JOIN scale_words a ON a.id=1+(g*7919)%%%s
                        JOIN scale_words b ON b.id=1+(g*104729)%%%s''', [OFFSET,start+1,min(start+50000,remaining),len(vocabulary),len(vocabulary)])
                print('artists', Artist.objects.count(), flush=True)
            artist_count = min(90000, Artist.objects.filter(pk__gte=OFFSET).count())
            c.execute('SELECT generated FROM scale_state WHERE id=1')
            generated = c.fetchone()[0]
            needed = max(0, target-Track.objects.count())
            began = time.monotonic()
            for start in range(generated+1, generated+needed+1, 25000):
                end = min(start+24999, generated+needed)
                # Dense releases: 24 per base title, including live/remix versions;
                # 90k active artist IDs approximate the pg_stats estimate.
                # This is a selectivity stress fixture, not a production copy.
                c.execute('''INSERT INTO tracks
                    (id,deezer_id,title,artist,deezer_artist_id,rank,has_preview,norm_title,norm_artist,
                     search_title,search_artist,contributors,is_curated,is_variant,created_at)
                    SELECT md5('scale-track-'||g)::uuid,%s+g,
                      CASE WHEN s%%12=0 THEN 'Love ' WHEN s%%12=1 THEN 'The ' ELSE '' END
                      ||a.word||' '||b.word||' '||d.word||
                      CASE WHEN g%%13=0 THEN ' (Live)' WHEN g%%17=0 THEN ' (Remix)' ELSE '' END,
                      p.name,p.deezer_id,(s*7919)%%1000000,g%%3<>0,
                      a.word||' '||b.word||' '||d.word,p.norm_name,'','','[]',false,g%%13=0 OR g%%17=0,now()
                    FROM generate_series(%s::bigint,%s::bigint) g
                    CROSS JOIN LATERAL (SELECT (g-1)/24 AS s) x
                    JOIN scale_words a ON a.id=1+(s*7919)%%%s
                    JOIN scale_words b ON b.id=1+((s/7)*104729)%%%s
                    JOIN scale_words d ON d.id=1+((s/31)*15485863)%%%s
                    JOIN artists p ON p.deezer_id=%s+1+s%%%s''', [OFFSET,start,end,len(vocabulary),len(vocabulary),len(vocabulary),OFFSET,artist_count])
                c.execute('UPDATE scale_state SET generated=%s WHERE id=1',[end])
                print('generated',end,'elapsed_s',round(time.monotonic()-began,1),flush=True)
    finally:
        with connection.cursor() as c:
            c.execute('ALTER TABLE tracks ENABLE TRIGGER search_track_event')
            c.execute('ALTER TABLE artists ENABLE TRIGGER search_artist_event')
    SearchOutbox.objects.all().delete()
    SearchEnrichment.objects.all().delete()
    call_command('search_backfill')
    with connection.cursor() as c:
        c.execute('VACUUM (ANALYZE) tracks')
        c.execute('VACUUM (ANALYZE) artists')
    print('ready', metadata(),flush=True)


def metadata():
    with connection.cursor() as c:
        c.execute("SELECT pg_database_size(current_database()), pg_table_size('tracks'), pg_indexes_size('tracks'), pg_table_size('artists'), pg_indexes_size('artists')")
        sizes = dict(zip(['database_bytes','tracks_heap_bytes','tracks_indexes_bytes','artists_heap_bytes','artists_indexes_bytes'],c.fetchone()))
    return dict(tracks=Track.objects.count(),artists=Artist.objects.count(),**sizes)


def run_query(item):
    connection.ensure_connection()
    with connection.cursor() as c:
        c.execute("SET statement_timeout='2500ms'")
    start = time.perf_counter()
    try:
        result = search(item.get('kind','tracks'),item['query'])
        ids = [str(t.deezer_id) for t in result['rows']]
        rank = next((i+1 for i,v in enumerate(ids) if v in item.get('expected',[])),None)
        return dict(expected=item.get('expected'),max_rank=item.get('max_rank'),split=item.get('split'),query=item['query'],kind=item.get('kind','tracks'),category=item.get('category'),ms=(time.perf_counter()-start)*1000,rank=rank,passed=rank is not None and rank<=item.get('max_rank',40),empty=not bool(ids),error=None)
    except DatabaseError as exc:
        return dict(expected=item.get('expected'),max_rank=item.get('max_rank'),split=item.get('split'),query=item['query'],kind=item.get('kind','tracks'),category=item.get('category'),ms=(time.perf_counter()-start)*1000,error=type(exc).__name__,message=str(exc)[:150],passed=False)


def summary(rows, elapsed):
    times=sorted(r['ms'] for r in rows)
    return dict(assertions=sum(bool(r.get('expected')) for r in rows),requests=len(rows),errors=sum(bool(r['error']) for r in rows),empty=sum(r.get('empty',False) for r in rows),passed=sum(r['passed'] for r in rows),seconds=elapsed,throughput=len(rows)/elapsed,response_p95_ms=sorted(r.get('response_ms',r['ms']) for r in rows)[min(len(rows)-1,int(len(rows)*.95))],p50_ms=statistics.median(times),p95_ms=times[min(len(times)-1,int(len(times)*.95))],p99_ms=times[min(len(times)-1,int(len(times)*.99))])


def explain(label):
    plans=[]
    for kind,query in [('tracks','li'),('tracks','love'),('tracks','nes'),('tracks','a tu'),('artists','ed sheran')]:
        statements=[]
        def capture(execute,sql,params,many,context):
            began=time.monotonic()
            try:
                return execute(sql,params,many,context)
            finally:
                if sql.startswith('SELECT'):
                    statements.append((sql,params,(time.monotonic()-began)*1000))
        with connection.execute_wrapper(capture):
            result=run_query(dict(kind=kind,query=query))
        for sql,params,elapsed in statements:
            if elapsed<10 and 'short_prefix' not in sql:
                continue
            with connection.cursor() as c:
                c.execute("SET statement_timeout='15s'")
                try:
                    c.execute('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) '+sql,params)
                    plan=c.fetchone()[0]
                except DatabaseError as exc:
                    plan=str(exc)
            plans.append(dict(kind=kind,query=query,original_ms=elapsed,sql=sql,params=params,plan=plan))
        print(kind,query,result['ms'],flush=True)
    (ROOT/(label+'.json')).write_text(json.dumps(plans,default=str,ensure_ascii=False,indent=2)+'\n')


def resource_snapshot():
    with connection.cursor() as c:
        c.execute("SELECT pg_read_file('/sys/fs/cgroup/cpu.stat'), pg_read_file('/sys/fs/cgroup/memory.current'), pg_read_file('/sys/fs/cgroup/memory.stat'), pg_read_file('/sys/fs/cgroup/memory.events'), pg_read_file('/sys/fs/cgroup/cpu.max')")
        db_cpu, db_memory, db_memory_stat, db_memory_events, db_cpu_max = c.fetchone()
    parse = lambda value: {line.split()[0]: int(line.split()[1]) for line in value.splitlines()}
    return dict(at=time.monotonic(), db_cpu=parse(db_cpu), db_memory=int(db_memory), db_cpu_max=db_cpu_max.strip(), app_cpu_max=Path('/sys/fs/cgroup/cpu.max').read_text().strip(), db_memory_stat=parse(db_memory_stat), db_memory_events=parse(db_memory_events),
                app_cpu=parse(Path('/sys/fs/cgroup/cpu.stat').read_text()),
                app_memory=int(Path('/sys/fs/cgroup/memory.current').read_text()))


def resource_summary(samples):
    first,last = samples[0],samples[-1]
    seconds = last['at']-first['at']
    result = {'samples':len(samples),'seconds':seconds,'db_cpu_quota':first['db_cpu_max'],'app_cpu_quota':first['app_cpu_max']}
    for side in ['db','app']:
        before,after = first[side+'_cpu'],last[side+'_cpu']
        result[side] = dict(peak_sampled_cpu_cores=max((b[side+'_cpu']['usage_usec']-a[side+'_cpu']['usage_usec'])/1e6/(b['at']-a['at']) for a,b in zip(samples,samples[1:])), average_cpu_cores=(after['usage_usec']-before['usage_usec'])/1e6/seconds,
            max_sampled_memory_bytes=max(s[side+'_memory'] for s in samples),
            throttled_periods=after.get('nr_throttled',0)-before.get('nr_throttled',0),
            scheduling_periods=after.get('nr_periods',0)-before.get('nr_periods',0))
    result['db']['memory_events_end']=last['db_memory_events']
    result['db']['memory_breakdown_end']=last['db_memory_stat']
    return result


def generated_queries(count):
    words=sorted({w for d in REAL['documents'] for w in normalize_query(d['title']).split() if len(w)>=3})
    with connection.cursor() as c:
        c.execute('SELECT generated FROM scale_state WHERE id=1')
        maximum=c.fetchone()[0]
    rng=random.Random(73)
    result=[]
    while len(result)<count:
        g=rng.randint(1,maximum);song=(g-1)//24;artist=1+song%90000
        if artist%1000==0:
            continue
        title=('Love ' if song%12==0 else 'The ' if song%12==1 else '')
        title+=' '.join([words[song*7919%len(words)],words[(song//7)*104729%len(words)],words[(song//31)*15485863%len(words)]])
        title+=' (Live)' if g%13==0 else ' (Remix)' if g%17==0 else ''
        name=f'{words[artist*7919%len(words)]} {words[artist*104729%len(words)]} {artist}'
        result.append(dict(query=title+' '+name,kind='tracks',category='generated_title_artist',split='generated',
            expected=[str(OFFSET+i) for i in range(song*24+1,min(song*24+25,maximum+1))],max_rank=5))
    return result


def measure(label, full, clients, repeat, rate, generated):
    queries=list(CORPUS['queries']) if full else [q for i,q in enumerate(CORPUS['queries']) if i%15==0]+CORPUS['queries'][-10:]
    if full:
        queries += [dict(q,expected=[str(int(i)+20_000_000) for i in q['expected']]) for q in REAL['queries']]
    extra=['love','the','intro','q&a','nes','drake','ed sheran','straykids','a tu','xyzzunfindable','li','sweet dreams are made of this']
    queries += [dict(query=q,kind=kind,category='traffic') for kind in ('tracks','artists') for q in extra]
    queries += generated_queries(generated) if generated else []
    random.Random(42).shuffle(queries)
    samples=[]
    resources=[resource_snapshot()]
    stop=threading.Event()
    def observe():
        try:
            while not stop.wait(1):
                resources.append(resource_snapshot())
        finally:
            connection.close()
    observer=threading.Thread(target=observe,daemon=True)
    observer.start()
    started=time.monotonic()
    # Rate is arrivals/sec, separately from closed-loop maximum throughput.
    def job(item, due):
        began=time.monotonic()
        row=run_query(item)
        row['queue_ms']=max(0,(began-due)*1000) if due else 0
        row['response_ms']=row['ms']+row['queue_ms']
        return row
    with ThreadPoolExecutor(max_workers=clients) as pool:
        futures=[]
        for i,q in enumerate(queries*repeat):
            due=started+i/rate if rate else None
            if due:
                time.sleep(max(0,due-time.monotonic()))
            futures.append(pool.submit(job,q,due))
        for i,f in enumerate(futures):
            samples.append(f.result())
            if i%25==0:print('measured',i+1,'errors',sum(bool(r['error']) for r in samples),flush=True)
    elapsed=time.monotonic()-started
    stop.set();observer.join(timeout=5)
    resources.append(resource_snapshot())
    report=dict(label=label,scope='Synthetic volume, local CPU quotas; not VPS hardware, disk, real traffic or HTTP end-to-end',metadata=metadata(),clients=clients,arrival_rate=rate,repeat=repeat,generated_queries=generated,summary=summary(samples,elapsed),resources=resource_summary(resources),
        categories={category:summary([r for r in samples if r.get('category')==category],elapsed)
                    for category in sorted({r.get('category') for r in samples if r.get('category')})},
        results=samples)
    (ROOT/(label+'.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report['summary']),flush=True)
    connections.close_all()


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('mode',choices=['seed','measure','explain','inventory'])
    parser.add_argument('--tracks',type=int,default=100000)
    parser.add_argument('--artists',type=int,default=778434)
    parser.add_argument('--label',default='postgres-scale')
    parser.add_argument('--full',action='store_true')
    parser.add_argument('--reset',action='store_true',help='Replace only this isolated synthetic database')
    parser.add_argument('--clients',type=int,default=1)
    parser.add_argument('--generated',type=int,default=0)
    parser.add_argument('--repeat',type=int,default=1)
    parser.add_argument('--rate',type=float,default=0)
    args=parser.parse_args()
    if args.mode=='seed':seed(args.tracks,args.artists,args.reset)
    elif args.mode=='inventory':
        report=metadata()
        with connection.cursor() as cursor:
            cursor.execute("SELECT indexrelid::regclass::text, pg_relation_size(indexrelid), indisvalid FROM pg_index WHERE indrelid IN ('tracks'::regclass,'artists'::regclass) ORDER BY indexrelid::regclass::text")
            report['indexes']=[dict(name=n,bytes=b,valid=v) for n,b,v in cursor.fetchall()]
        (ROOT/(args.label+'.json')).write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(report),flush=True)
    elif args.mode=='explain':explain(args.label)
    else:measure(args.label,args.full,args.clients,args.repeat,args.rate,args.generated)
