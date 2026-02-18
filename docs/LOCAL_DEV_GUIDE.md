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
   python manage.py fetch_deezer_tracks --count 200
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
- Python (compatible with Django 6.0.x)
- `pip` and `virtualenv`
- Optional: Redis (only needed for Celery tasks like stem generation)
- Optional: Demucs (for stem generation; included in `requirements.txt`)

### Environment File
Create `songspot_backend/.env` with at least:
```env
DJANGO_SECRET_KEY=dev-secret
DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1

# Optional (only needed if you run Celery)
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0

# Optional stem cleanup TTL (hours)
STEM_TTL_HOURS=72
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
The game requires tracks in the database:
```bash
python manage.py fetch_deezer_tracks --count 200
```

If you see errors like “No tracks available”, run the command above again.

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

---

## Optional: Celery + Redis (Stem Generation)

Stem generation runs asynchronously via Celery.

1. Start Redis (use your OS package manager or Docker).
2. In `songspot_backend`, run a worker:
   ```bash
   celery -A songspot worker -l info
   ```

If you are not generating stems, you can skip Redis + Celery entirely.

---

## Optional: Stem Generation (Packs)

Stems are stored under `MEDIA_ROOT` and served from `/media/` when `DEBUG=True`.
The CLI requires `demucs` on `PATH`.

Examples:
```bash
python manage.py generate_pack_stems --pack-track-id <PACK_TRACK_UUID>
python manage.py generate_pack_stems --pack-id <PACK_UUID>
python manage.py generate_pack_stems --all --missing-only
```

If `demucs` fails to write MP3s, install `ffmpeg` and retry.

More details: `docs/STEMS_GUIDE.md`.

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
docker compose up --build -d
```

### Run Backend Setup Commands in Container
`docker-compose.yml` runs `python manage.py migrate` automatically before `runserver` on backend startup.
You still need to seed track data manually:
```bash
docker compose exec backend python manage.py fetch_deezer_tracks --count 200
```

### Open a Shell in the Container
```bash
docker compose exec backend sh
```

### Run Demucs (or Any Other Command) in Container
```bash
docker compose exec backend demucs --help
docker compose exec backend python manage.py generate_pack_stems --all --missing-only
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

---

## Troubleshooting

### 401/403 or WebSocket errors
- Ensure `ALLOWED_HOSTS` includes your host/IP.
- Confirm the mobile `API_BASE_URL` matches your backend host.

### 429 Too Many Requests
DRF throttling is enabled by default.
You can disable it in local dev (see `docs/THROTTLING.md`).

### Missing Audio / Packs
- Run `python manage.py fetch_deezer_tracks --count 200`.
- For packs, see `docs/STEMS_GUIDE.md`.

---

## References
- `docs/API_DOCUMENTATION.md`
- `docs/GAME_API_DOCUMENTATION.md`
- `docs/THROTTLING.md`
- `docs/STEMS_GUIDE.md`
