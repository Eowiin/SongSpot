# SongSpot Local Development Setup

Quick guide to get the full stack running on your machine.

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Python | 3.12 | `python3 --version` |
| Flutter | >= 3.9.2 | `flutter --version` |
| Redis | 7+ | For Celery + WebSocket channels |
| FFmpeg | any | Required by demucs for audio processing |

### Install Redis (macOS)

```bash
brew install redis
brew services start redis
```

### Install FFmpeg (macOS)

```bash
brew install ffmpeg
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

# Redis (make sure Redis is running)
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0
USE_REDIS_CHANNEL_LAYER=True
CHANNEL_LAYERS_REDIS_URL=redis://localhost:6379/1

# Optional: Firebase push notifications (leave blank to skip)
# FCM_SERVICE_ACCOUNT_PATH=/path/to/firebase-service-account.json
```

No `DATABASE_URL` needed — defaults to SQLite for local dev.

### Run migrations and seed data

```bash
source .venv/bin/activate
python manage.py migrate
python manage.py createsuperuser
python manage.py fetch_deezer_tracks --count 50
python manage.py update_track_metadata --dry-run
python manage.py update_track_metadata
python manage.py seed_genre_packs --count-per-pack 10 --genres pop,rock
```

### Start the backend (Daphne)

Use Daphne instead of `runserver` — it supports WebSockets properly:

```bash
source .venv/bin/activate
daphne -b 0.0.0.0 -p 8000 songspot.asgi:application
```

> **Note:** `manage.py runserver` works for REST endpoints but has limited WebSocket support. Always use Daphne when testing WebSocket features (chat, stems ready notifications).

### Start the Celery worker (separate terminal)

Required for async tasks (stem generation, push notifications):

```bash
cd songspot_backend
source .venv/bin/activate
celery -A songspot worker -l info
```

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

Open 3 terminal tabs:

```bash
# Tab 1: Backend
cd songspot_backend && source .venv/bin/activate
daphne -b 0.0.0.0 -p 8000 songspot.asgi:application

# Tab 2: Celery worker
cd songspot_backend && source .venv/bin/activate
celery -A songspot worker -l info

# Tab 3: Mobile
cd songspot_mobile && flutter run
```

Redis must already be running (`brew services start redis`).

---

## 4. Alternative: Docker for backend

The `docker-compose.yml` at the repo root can spin up backend + celery + redis together:

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
| Celery tasks not running | Check Redis is running: `redis-cli ping` |
| Mobile can't reach backend | Use local IP (not `localhost`) in `.env` |
| Stem generation fails | Ensure FFmpeg is installed: `ffmpeg -version` |
| Push notifications not working | Need `FCM_SERVICE_ACCOUNT_PATH` set in `.env` |

---

## Management Commands Reference

| Command | Description |
|---------|-------------|
| `python manage.py migrate` | Run database migrations |
| `python manage.py createsuperuser` | Create admin account |
| `python manage.py fetch_deezer_tracks --count N` | Populate tracks from Deezer |
| `python manage.py update_track_metadata [--dry-run] [--search-missing]` | Backfill `genre`, `release_year`, cover URL, and missing `deezer_id` on existing tracks |
| `python manage.py seed_genre_packs --count-per-pack N --genres pop,rock` | Create song packs |
| `python manage.py generate_pack_stems --all --missing-only` | Generate stems (batch) |
| `python manage.py prepare_daily_content` | Create daily songs for all rooms |
| `python manage.py cleanup_stems --max-age-hours 72` | Delete old stem files |

---

## Scaling for Production

This section documents what to consider when the app outgrows a single VPS.

### Current Architecture (single VPS)

```
[Nginx] -> [Daphne (ASGI)] -> [Django + Channels]
                             -> [Celery worker] -> [Redis broker]
                             -> [PostgreSQL]
```

Everything runs on one server. This handles ~100-500 concurrent users depending on VPS specs.

### When to Scale

| Signal | What it means |
|--------|--------------|
| Stem generation queue backs up | Celery workers are CPU-bottlenecked (demucs is heavy) |
| WebSocket connections drop under load | Daphne is hitting connection limits |
| API response times increase | Database or application server is overloaded |
| Disk space fills up | Stem files accumulating faster than cleanup |

### Step 1: Separate Celery Workers

The easiest first move. Stem generation (demucs + PyTorch) is the heaviest workload.

- Spin up a second VPS dedicated to Celery workers
- Point it to the same Redis broker (open Redis port or use a managed Redis)
- Scale workers horizontally — add more VPS instances as needed
- Consider GPU instances for faster stem generation

```
[VPS 1: Nginx + Daphne + Django + PostgreSQL]
[VPS 2: Celery worker] ---> [Redis (VPS 1 or managed)]
[VPS 3: Celery worker] -/
```

### Step 2: Managed Database

Move PostgreSQL off the app server:

- Use a managed service (e.g., DigitalOcean Managed PostgreSQL, AWS RDS)
- Handles backups, failover, and connection pooling
- Update `DATABASE_URL` in `.env` to point to the managed instance

### Step 3: Managed Redis

Same idea — offload Redis:

- Managed Redis (e.g., DigitalOcean Managed Redis, AWS ElastiCache)
- Ensures Redis persistence and high availability
- Update `CELERY_BROKER_URL` and `CHANNEL_LAYERS_REDIS_URL`

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

### Step 5: Object Storage for Stems

Stem files are large and temporary:

- Move stems to S3-compatible storage (e.g., DigitalOcean Spaces, AWS S3)
- Serve via CDN for faster downloads
- Use `django-storages` with `S3Boto3Storage` backend
- Reduces disk pressure on the app server

### Step 6: CDN for Static/Media

- Put Cloudflare or similar CDN in front of Nginx
- Cache static files, media, and stem downloads at the edge
- Reduces bandwidth costs and improves mobile app load times

### What NOT to Do Yet

- **Don't Dockerize/Kubernetes** until you have 3+ servers to manage — adds complexity without benefit at small scale
- **Don't add a separate API gateway** — Nginx already handles routing, SSL, and WebSocket upgrade
- **Don't shard the database** — PostgreSQL handles millions of rows easily; optimize queries first
- **Don't premature-optimize** — monitor first (add basic logging/metrics), then scale the actual bottleneck
