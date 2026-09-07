# Local Development Guide

This guide walks through running the SongSpot backend and mobile app locally.
It focuses on the fastest path to a working dev loop.

---

## Quick Start (Backend + Mobile)

1. Backend (from repo root):
   ```bash
   cd songspot_backend
   python -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   # Create songspot_backend/.env (see Backend Setup below)
   python manage.py migrate
   python manage.py createsuperuser
   python manage.py seed_curated_artists
   python manage.py runserver
   ```

2. Mobile (new terminal):
   ```bash
   cd songspot_mobile
   flutter pub get
   cp .env.example .env
   # Update API_BASE_URL in .env (see Mobile Setup)
   flutter run
   ```

---

## Backend Setup (Django)

### Prerequisites
- Python 3.12
- `pip` and `virtualenv`
- Postgres 16 — prod runs it, and the search indexes are `pg_trgm` + GIN, which
  SQLite has neither of. `docker compose up` gives you one.
- Optional: Redis (websocket channel layer and Django cache)

### Environment File
Create `songspot_backend/.env` with at least:
```env
DJANGO_SECRET_KEY=dev-secret
DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1

# Match prod rather than falling back to SQLite
DATABASE_URL=postgres://songspot:songspot@localhost:5433/songspot

# Optional websocket fan-out for multi-process ASGI
USE_REDIS_CHANNEL_LAYER=True
CHANNEL_LAYERS_REDIS_URL=redis://localhost:6379/1

# Optional push notifications (FCM)
# FCM_SERVICE_ACCOUNT_PATH=/absolute/path/to/firebase-service-account.json
# OR
# FCM_SERVICE_ACCOUNT_JSON={"type":"service_account", ...}
```

Notes:
- `ALLOWED_HOSTS` is used by HTTP and WebSocket validation in local dev.
- SQLite is the default database (no extra setup required).

### Install + Migrate
```bash
cd songspot_backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py createsuperuser
```

### Seed Track Data (Required for Gameplay)
The game requires tracks in the database. Seed from the curated artist list:
```bash
python manage.py seed_curated_artists           # ~190 artists, 10 tracks each
python manage.py seed_curated_artists --tracks 20  # more tracks per artist
```

To add a single artist on demand:
```bash
python manage.py add_artist “Rosalía” --tracks 15
python manage.py add_artist “Rosalía” --tracks 15 --save-to-list  # also adds to curated_artists.json
```

To delete all tracks and start fresh:
```bash
python manage.py shell -c “from game.models import Track; Track.objects.all().delete()”
```

### Run the Server
```bash
python manage.py runserver
```

The API will be available at `http://localhost:8000/api/`.
If you need LAN access (physical device testing), run:
```bash
python manage.py runserver 0.0.0.0:8000
```
and add your LAN IP (and `0.0.0.0` if needed) to `ALLOWED_HOSTS`.

### WebSocket Notes

- `runserver` is enough for local websocket development.
- For production-style local runs, use ASGI directly:

```bash
daphne -b 0.0.0.0 -p 8000 songspot.asgi:application
```

- If you run multiple ASGI workers/instances, use Redis channel layer (`USE_REDIS_CHANNEL_LAYER=True`) instead of in-memory.

---

## Optional: Redis

Redis backs the websocket channel layer (`USE_REDIS_CHANNEL_LAYER=True`) and the
Django cache. Neither is required for a single-process dev server, which falls
back to an in-memory layer and a local-memory cache.

`docker compose up` starts one for you; otherwise use your OS package manager.

For push notifications, you also need Firebase server credentials in `songspot_backend/.env`:
```env
FCM_SERVICE_ACCOUNT_PATH=/absolute/path/to/firebase-service-account.json
```
or
```env
FCM_SERVICE_ACCOUNT_JSON={"type":"service_account", ...}
```

iOS note:
- APNs `.p8` key is the recommended setup in Firebase (Cloud Messaging tab).
- `.p12` certificates are optional legacy alternative.

---

## Backend via Docker Compose (CPU/Memory Limit Testing)

If you want to test backend behavior under constrained resources, use the root `docker-compose.yml`.

### Configure Limits
Edit the `backend` service in `docker-compose.yml`:
```yaml
cpus: "4.0"
mem_limit: 8g
```
Change these values to the limits you want to test.

### Start Backend Container
From repo root:
```bash
export FCM_SERVICE_ACCOUNT_PATH=/absolute/path/to/firebase-service-account.json
docker compose up --build -d
```

This starts:
- `backend` (Django + Daphne)
- `db` (Postgres 16, published on host port 5433)
- `redis`

### Run Backend Setup Commands in Container
`docker-compose.yml` runs `python manage.py migrate` automatically before `runserver` on backend startup.
You still need to fill the catalogue manually:
```bash
docker compose exec backend python manage.py refresh_catalog
```

### Open a Shell in the Container
```bash
docker compose exec backend sh
```

### Run Any Other Command in the Container
```bash
docker compose exec backend python manage.py <command>
```

### Stop Containers
```bash
docker compose down
```

---

## Mobile Setup (Flutter)

### Prerequisites
- Flutter SDK (see `songspot_mobile/README.md`)
- iOS Simulator or Android Emulator (or a physical device)

### Configure API Base URL
`songspot_mobile` uses `.env`:
```bash
cd songspot_mobile
cp .env.example .env
```

Set `API_BASE_URL` in `songspot_mobile/.env`:
```env
API_BASE_URL=http://YOUR_IP_ADDRESS:8000/api
```

Examples:
- iOS Simulator: `http://localhost:8000/api`
- Android Emulator: `http://10.0.2.2:8000/api`
- Physical device: `http://<your-lan-ip>:8000/api`

### Run the App
```bash
flutter pub get
flutter run
```

### FCM Files (Optional for Push)
- Android: place `google-services.json` in `songspot_mobile/android/app/`
- iOS: add `GoogleService-Info.plist` to `songspot_mobile/ios/Runner/` and enable push capabilities in Xcode.
- These Firebase client config files are gitignored and should stay local-only.
- Full guide: `docs/PUSH_NOTIFICATIONS.md`

---

## Troubleshooting

### 401/403 or WebSocket errors
- Ensure `ALLOWED_HOSTS` includes your host/IP.
- Confirm the mobile `API_BASE_URL` matches your backend host.

### 429 Too Many Requests
DRF throttling is enabled by default.
You can disable it in local dev (see `docs/THROTTLING.md`).

### Missing Audio / Packs
- Run `python manage.py seed_curated_artists`.
- For packs, see `docs/STEMS_GUIDE.md`.

---

## References
- `docs/API_DOCUMENTATION.md`
- `docs/GAME_API_DOCUMENTATION.md`
- `docs/THROTTLING.md`
- `docs/STEMS_GUIDE.md`
- `docs/PUSH_NOTIFICATIONS.md`
