"""Read workload on the isolated synthetic database; no provider calls."""
import json
import time
from pathlib import Path
from postgres_scale import connection, metadata, resource_snapshot, resource_summary
from game.services.search import search

queries = ['yo', 'li', 'lo', 'th', 'an', 'in', 'de', 'la', 'on', 'be', 'we', 'to', 'zx', 'qz', 'xq']
report = {'scope': 'Local synthetic catalogue, 2 CPU/3 GiB PostgreSQL; no provider',
          'metadata': metadata(), 'queries': []}
resources = [resource_snapshot()]
for query in queries:
    durations = []
    for attempt in range(3):
        with connection.cursor() as cursor:
            cursor.execute("SET statement_timeout='5000ms'")
        start = time.perf_counter()
        result = search('tracks', query, enqueue=False)
        durations.append(round((time.perf_counter()-start)*1000, 2))
    row = {'query': query, 'ms': durations, 'results': len(result['rows'])}
    report['queries'].append(row)
    resources.append(resource_snapshot())
    print(row, flush=True)
with connection.cursor() as cursor:
    cursor.execute("SELECT pg_relation_size('tracks_search_words')")
    report['word_index_bytes'] = cursor.fetchone()[0]
    cursor.execute("SELECT pg_relation_size('tracks_search_rank')")
    report['rank_index_bytes'] = cursor.fetchone()[0]
    report['plans'] = {}
    for query in ('yo', 'li', 'qz'):
        cursor.execute("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT id FROM tracks WHERE to_tsvector('simple', search_title || ' ' || search_artist) @@ to_tsquery('simple', %s) ORDER BY rank DESC, id LIMIT 200", [query + ':*'])
        report['plans'][query] = cursor.fetchone()[0]
report['resources'] = resource_summary(resources)
Path('/workspace/docs/search/postgres-short-words.json').write_text(json.dumps(report, indent=2)+'\n')
