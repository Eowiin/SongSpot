# Isolated search verification

All mutations target the `search_test` database created by this stack. Never use
production `.env` files or the production endpoints. Ports bind to localhost.
Requires Docker; runner uses the repository's backend image (Django 6.0.1,
Python 3.12, dependencies in `songspot_backend/requirements.txt`). If absent:

```sh
docker build -t songspot-backend:latest -f songspot_backend/Dockerfile .
git show 2347009:songspot_backend/game/services/catalog.py > /tmp/songspot-search-baseline.py
docker compose -p songspot-search -f scripts/search_benchmark/compose.yml up -d db typesense meili
docker compose -p songspot-search -f scripts/search_benchmark/compose.yml run --rm runner /workspace/scripts/search_benchmark/run.py baseline
docker compose -p songspot-search -f scripts/search_benchmark/compose.yml run --rm runner /workspace/scripts/search_benchmark/run.py engines
docker compose -p songspot-search -f scripts/search_benchmark/compose.yml run --rm runner /workspace/scripts/search_benchmark/run.py postgres
docker compose -p songspot-search -f scripts/search_benchmark/compose.yml run --rm runner /workspace/scripts/search_benchmark/run.py integrated
docker compose -p songspot-search -f scripts/search_benchmark/compose.yml run --rm runner /workspace/scripts/search_benchmark/load.py
docker compose -p songspot-search -f scripts/search_benchmark/compose.yml run --rm runner /workspace/scripts/search_benchmark/integration.py
```

`run.py` replaces musical rows in the isolated database. Never run two benchmark
runners simultaneously. `load.py` adds 25,000 synthetic titles; run `integration.py`
after it. Add `-e CORPUS_FILE=local-real-corpus.json -e REPORT_PREFIX=real-` before
`runner` to compare the existing local musical snapshot. This snapshot contains
only music metadata, no accounts, URLs, tokens or personal data. The exporter
opens SQLite with `mode=ro` and a 6,000-row bound.

Synthetic corpus v2 changes the assertion for ambiguous `INTRO`/`Hello` from
rank <=5 to <=20. This corrects the annotation to match the original plan, not
the search implementation. The unchanged v1 baseline and engine results retain
their original assertions for traceability. Recall and MRR are unaffected.
Unambiguous title+artist and the explicit q&a rank-1 requirement are unchanged.
The additional 200 real title+artist queries are held out from tuning.

Measured load is a closed-loop test with eight threads, 930 requests and a new
PostgreSQL connection per request. First query does not mean cold OS cache.
The measured size is much smaller than production. Container `memory.peak`
includes startup, indexing and page cache; `du` includes retained generations.

Stop only this stack when finished:

```sh
docker compose -p songspot-search -f scripts/search_benchmark/compose.yml down
```

## PostgreSQL at catalogue scale (no Meilisearch)

The separate `postgres-scale.yml` has an internal Docker network, no published
ports and no provider/index worker. Its PostgreSQL is limited to 2 CPU cores and
3 GiB with no swap, and the runner to 1 CPU core and 512 MiB. PostgreSQL settings
match the read-only VPS snapshot: shared_buffers 1 GiB, work_mem 4 MiB, effective
cache 2500 MiB, two parallel workers per gather. These are CPU quotas on a local
Ryzen, not an emulation of the VPS EPYC CPU or its shared disk.

```sh
docker compose -p songspot-pgscale -f scripts/search_benchmark/postgres-scale.yml up -d db
docker compose -p songspot-pgscale -f scripts/search_benchmark/postgres-scale.yml run --rm runner seed --tracks 3780448 --reset
docker compose -p songspot-pgscale -f scripts/search_benchmark/postgres-scale.yml run --rm runner measure --full --generated 500 --label postgres-3780k-quality
docker compose -p songspot-pgscale -f scripts/search_benchmark/postgres-scale.yml run --rm runner measure --clients 8 --rate 2 --repeat 3 --label postgres-3780k-2rps
docker compose -p songspot-pgscale -f scripts/search_benchmark/postgres-scale.yml run --rm runner measure --clients 8 --repeat 12 --label postgres-3780k-burst
docker compose -p songspot-pgscale -f scripts/search_benchmark/postgres-scale.yml down
```

`--reset` replaces only the synthetic database guarded by database name and host.
It never belongs on the production server. The volume is retained when stopped.
The seed includes the 282 synthetic musical fixtures, 5,363 local musical rows,
and generated titles from their vocabulary. The final dense generator assigns
24 releases per base title, with live/remix variants, to 90,000 active synthetic
artist identities, among 778,434 artist rows total. These approximations use
planner statistics, not a copy of production distributions. The earlier 100k
and 1m probes used three releases per base title and more active artists: do not
interpret them as a controlled scaling curve of the final dataset.

During snapshot construction only, projection event triggers are disabled in
this isolated database and restored in `finally`; normalization remains active.
This measures query performance, not live import throughput. A 2.5-second SQL
statement timeout bounds pathological searches; timeout errors are reported,
not silently removed from latency statistics. Search includes durable enqueue
operations, with no provider calls. Query functions are measured directly,
without HTTP/mobile latency. Worker threads reuse their SQL connections.

`--full` tests all 510 existing assertions plus 24 traffic probes. The shorter
load mix includes 31 corpus queries and the same 24 probes (title and artist,
short/common/unknown/typo). At a specified arrival rate, queue delay is reported
separately and included in `response_p95_ms`; without a rate, the pool stays busy
as a closed-loop load. Neither mix is claimed to reproduce user traffic.

Resource samples read only the isolated containers' cgroup counters every second.
CPU is expressed in consumed local core equivalents (1 = one fully occupied
core), with quota/throttling counters. Memory includes charged file cache and
shared memory; it is not all non-reclaimable heap, nor the incremental RAM that
would be required on the VPS. Database size includes pre-existing and new
indexes. Warm runs and restarts do not flush the host OS page cache.

`--generated 500` adds 500 deterministic complete title+artist queries spread
across the generated catalogue. Their texts are computed from the generator
formula without fetching the corresponding rows before measurement. Expected
IDs include releases of that same generated song/artist. Blocked artists are
excluded from these positive controls. This strengthens volume coverage without
pretending that synthetic titles measure real-world spelling quality.

For the reduced CPU scenario, after other runners have finished:

```sh
docker update --cpus 1 songspot-pgscale-db-1
APP_CPUS=0.5 docker compose -p songspot-pgscale -f scripts/search_benchmark/postgres-scale.yml run --rm runner measure --clients 8 --rate 2 --repeat 3 --label postgres-3780k-halfcpu-2rps
docker update --cpus 2 songspot-pgscale-db-1
```
