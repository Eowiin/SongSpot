"""Read only musical columns from the existing local SQLite catalogue."""
import hashlib,json,sqlite3
from pathlib import Path
root=Path(__file__).resolve().parents[2]
c=sqlite3.connect(f'file:{root}/songspot_backend/db.sqlite3?mode=ro',uri=True)
rows=c.execute('SELECT id,title,artist,deezer_artist_id,rank FROM tracks ORDER BY id LIMIT 6000').fetchall()
unknown={}
docs=[]
for i,(source_id,title,artist,aid,rank) in enumerate(rows):
    if not aid:aid=unknown.setdefault(artist,-1-len(unknown))
    docs.append(dict(id=str(i+1),source_id=source_id,title=title,artist=artist,artist_id=str(aid),rank=rank))
queries=[]
# Held out from tuning: deterministic 200-record sample, no query-log inference.
for d in sorted(docs,key=lambda d:hashlib.sha256(d['source_id'].encode()).hexdigest())[:200]:
    expected=[r['id'] for r in docs if r['title']==d['title'] and r['artist_id']==d['artist_id']]
    queries.append(dict(query=d['title']+' '+d['artist'],kind='tracks',category='title_artist',expected=expected,split='validation',max_rank=5))
(root/'docs/search/local-real-corpus.json').write_text(json.dumps(dict(schema=1,provenance='5363 musical rows read from pre-existing local SQLite, not a production sample. Fixture numeric IDs map to source music UUIDs; unknown artists grouped by stored credit only for the benchmark.',documents=docs,queries=queries),ensure_ascii=False,indent=2)+'\n')
