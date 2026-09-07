# SongSpot Local Development Setup

Quick guide to get the full stack running on your machine.

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Python | 3.12 | `python3 --version` |
| Flutter | >= 3.9.2 | `flutter --version` |
| PostgreSQL | 16 | Matches prod; SQLite lacks the `pg_trgm` search indexes |
| Redis | 7+ | WebSocket channel layer and Django cache |

### Install Redis (macOS)

```bash
brew install redis
brew services start redis
```

---

## 1. Backend

### Create virtualenv and install dependencies

```bash
cd songspot_backend
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Configure environment

```bash
cp .env.example .env
```

Edit `.env`:
```env
DJANGO_SECRET_KEY=any-random-string-for-dev
DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1,0.0.0.0

# Postgres, so local matches prod. `docker compose up` publishes it on 5433.
DATABASE_URL=postgres://songspot:songspot@localhost:5433/songspot

# Redis (make sure Redis is running)
USE_REDIS_CHANNEL_LAYER=True
CHANNEL_LAYERS_REDIS_URL=redis://localhost:6379/1

# Optional: Firebase push notifications (leave blank to skip)
# FCM_SERVICE_ACCOUNT_PATH=/path/to/firebase-service-account.json
```

Without `DATABASE_URL` the backend falls back to SQLite. That works for most
day-to-day development, but the search indexes (`pg_trgm` + GIN) and the
migrations that build them exist only on Postgres, so anything touching search
or a migration has to be exercised against Postgres before it ships.

### Run migrations and seed data

```bash
source .venv/bin/activate
python manage.py migrate
python manage.py createsuperuser
python manage.py refresh_catalog          # fill the category pools from Deezer
```

### Start the backend (Daphne)

Use Daphne instead of `runserver` — it supports WebSockets properly:

```bash
source .venv/bin/activate
daphne -b 0.0.0.0 -p 8000 songspot.asgi:application
```

> **Note:** `manage.py runserver` works for REST endpoints but has limited WebSocket support. Always use Daphne when testing WebSocket features.

---

## 2. Mobile App

### Configure environment

```bash
cd songspot_mobile
cp .env.example .env
```

Edit `.env` — use your machine's local IP (not `localhost`, since the phone/simulator needs to reach it):

```env
API_BASE_URL=http://192.168.x.x:8000/api
```

Find your local IP:
```bash
# macOS
ipconfig getifaddr en0
```

### Install dependencies and run

```bash
flutter pub get
flutter run
```

---

## 3. Quick Start (all-in-one)

Open 2 terminal tabs:

```bash
# Tab 1: Backend
cd songspot_backend && source .venv/bin/activate
daphne -b 0.0.0.0 -p 8000 songspot.asgi:application

# Tab 2: Mobile
cd songspot_mobile && flutter run
```

Postgres and Redis must already be running, or use `docker compose up` for both.

---

## 4. Alternative: Docker for backend

The `docker-compose.yml` at the repo root spins up backend + Postgres + Redis together:

```bash
docker compose up
```

This is convenient for quick testing but slower for iterating (no live reload). Best used when you only need to work on the mobile app and want the backend running in the background.

Run backend management commands inside Docker with:

```bash
docker compose exec backend python manage.py <command>
```

Examples:

```bash
docker compose exec backend python manage.py fetch_deezer_tracks --count 50
docker compose exec backend python manage.py update_track_metadata --dry-run
docker compose exec backend python manage.py update_track_metadata
docker compose exec backend python manage.py update_track_metadata --search-missing
```

---

## Common Gotchas

| Issue | Fix |
|-------|-----|
| WebSocket not connecting | Use Daphne, not `runserver` |
| Mobile can't reach backend | Use local IP (not `localhost`) in `.env` |
| Migration passes locally, fails on the VPS | You are on SQLite; run against Postgres (`docker compose up`) |
| Push notifications not working | Need `FCM_SERVICE_ACCOUNT_PATH` set in `.env` |

---

## Management Commands Reference

| Command | Description |
|---------|-------------|
| `python manage.py migrate` | Run database migrations |
| `python manage.py createsuperuser` | Create admin account |
| `python manage.py refresh_catalog [--category X] [--replace] [--dry-run]` | Refill the category pools from Deezer |
| `python manage.py crawl_artists` | Widen the catalogue along Deezer's artist graph |
| `python manage.py link_legacy_artists` | Give seeded tracks a Deezer artist id |
| `python manage.py backfill_artist_pictures` | Fill artwork missing on `artists` |
| `python manage.py update_track_metadata [--dry-run] [--search-missing]` | Backfill `genre`, `release_year`, cover URL, missing `deezer_id` |
| `python manage.py prepare_daily_content` | Create daily songs for all rooms |

---

## Scaling for Production

This section documents what to consider when the app outgrows a single VPS.

### Current Architecture (single VPS)

```
[Nginx] -> [Daphne (ASGI)] -> [Django + Channels]
                             -> [Redis]       (channel layer + cache)
                             -> [PostgreSQL]

[systemd timers] -> refresh_catalog / crawl_artists / rebuild
```

Everything runs on one server. There is no task queue: the catalogue jobs run as
`systemd` oneshots on timers, which is why there is no broker and no worker to
scale. This handles ~100-500 concurrent users depending on VPS specs.

### When to Scale

| Signal | What it means |
|--------|--------------|
| Load average climbs with search traffic | Query cost, not capacity — read Step 1 before buying hardware |
| WebSocket connections drop under load | Daphne is hitting connection limits |
| API response times increase | Database or application server is overloaded |

### Step 1: Fix the Queries First

Cheaper than any server. Track search runs `LIKE '%term%'` across four columns;
the `pg_trgm` GIN indexes from migration 0014 only apply when the predicate is
shaped to use them, and a term under three characters cannot use a trigram index
at all. A single slow search pattern will saturate a 4-core box long before
concurrency does.

Measure with `EXPLAIN (ANALYZE, BUFFERS)` and `pg_stat_activity` before
concluding you need more machines.

### Step 2: Managed Database

Move PostgreSQL off the app server:

- Use a managed service (e.g., DigitalOcean Managed PostgreSQL, AWS RDS)
- Handles backups, failover, and connection pooling
- Update `DATABASE_URL` in `.env` to point to the managed instance

### Step 3: Managed Redis

Same idea — offload Redis:

- Managed Redis (e.g., DigitalOcean Managed Redis, AWS ElastiCache)
- Ensures Redis persistence and high availability
- Update `CHANNEL_LAYERS_REDIS_URL`

### Step 4: Multiple Daphne Instances

If WebSocket/API load is the bottleneck:

- Run multiple Daphne processes behind Nginx (upstream block with multiple backends)
- Redis channel layer already handles cross-process WebSocket fan-out
- Add a load balancer if scaling across multiple VPS

```nginx
upstream asgi {
    server 127.0.0.1:8001;
    server 127.0.0.1:8002;
    server 127.0.0.1:8003;
}
```

### Step 5: CDN for Static/Media

- Put Cloudflare or similar CDN in front of Nginx
- Cache static files and media at the edge
- Reduces bandwidth costs and improves mobile app load times

### What NOT to Do Yet

- **Don't Dockerize/Kubernetes** until you have 3+ servers to manage — adds complexity without benefit at small scale
- **Don't add a separate API gateway** — Nginx already handles routing, SSL, and WebSocket upgrade
- **Don't shard the database** — PostgreSQL handles millions of rows easily; optimize queries first
- **Don't premature-optimize** — monitor first (add basic logging/metrics), then scale the actual bottleneck
