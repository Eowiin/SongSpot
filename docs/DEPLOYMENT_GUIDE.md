# SongSpot Deployment Guide

Guide for deploying SongSpot to a VPS with PostgreSQL, Redis, HTTPS, and CI/CD.

**Paths used throughout:** repo lives at `/var/www/songspot`, virtualenv at `/var/www/songspot/songspot_backend/.venv`.

---

## 1. PostgreSQL Setup

### Install PostgreSQL

```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo systemctl enable postgresql
sudo systemctl start postgresql
```

### Create Database and User

```bash
sudo -u postgres psql
```

```sql
CREATE DATABASE songspot;
CREATE USER songspot_user WITH PASSWORD 'your_secure_password_here';
ALTER ROLE songspot_user SET client_encoding TO 'utf8';
ALTER ROLE songspot_user SET default_transaction_isolation TO 'read committed';
ALTER ROLE songspot_user SET timezone TO 'UTC';
GRANT ALL PRIVILEGES ON DATABASE songspot TO songspot_user;
\q
```

### Configure Django

Add to your production `.env`:
```env
DATABASE_URL=postgres://songspot_user:your_secure_password_here@localhost:5432/songspot
```

`settings.py` reads `DATABASE_URL` automatically and falls back to sqlite3 for local dev:
```python
DATABASES = {
    'default': dj_database_url.config(
        default=f'sqlite:///{BASE_DIR / "db.sqlite3"}'
    )
}
```

### Run Migrations

```bash
cd /var/www/songspot/songspot_backend
source .venv/bin/activate
python manage.py migrate
python manage.py createsuperuser
```

---

## 2. Redis

### Install Redis

```bash
sudo apt install redis-server
sudo systemctl enable redis-server
sudo systemctl start redis-server
```

### Configure Env Vars

Add to `.env`:
```env
USE_REDIS_CHANNEL_LAYER=True
CHANNEL_LAYERS_REDIS_URL=redis://localhost:6379/1
```

---

## 3. HTTPS with Let's Encrypt

### Install Certbot

```bash
sudo apt install certbot python3-certbot-nginx
```

### Get SSL Certificate

```bash
sudo certbot --nginx -d api.yourdomain.com
```

### Auto-Renewal

```bash
sudo certbot renew --dry-run
sudo systemctl status certbot.timer
```

---

## 4. Nginx Configuration

### Install Nginx

```bash
sudo apt install nginx
```

### Create Site Config

> **Subdomain setup:** The backend runs on a dedicated subdomain, e.g. `api.yourdomain.com`.
> Point an `A` record for `api.yourdomain.com` at your VPS IP before running Certbot.

Create `/etc/nginx/sites-available/songspot`:
```nginx
upstream asgi {
    server 127.0.0.1:8000;
}

# Redirect HTTP → HTTPS
server {
    listen 80;
    server_name api.yourdomain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.yourdomain.com;

    ssl_certificate     /etc/letsencrypt/live/api.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.yourdomain.com/privkey.pem;

    # Recommended SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    # REST API
    location / {
        proxy_pass http://asgi;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket
    location /ws/ {
        proxy_pass http://asgi;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 86400;
    }

    # Static files
    location /static/ {
        alias /var/www/songspot/static/;
    }

    # Media files
    location /media/ {
        alias /var/www/songspot/songspot_backend/media/;
    }

    # AdMob verification file:
    # /app-ads.txt is served by Django (songspot.urls -> app_ads_txt)
    # Keep this route publicly reachable over HTTPS.
}
```

### Enable Site

```bash
sudo ln -s /etc/nginx/sites-available/songspot /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

---

## 5. ASGI Server (Daphne)

Daphne serves both REST and WebSocket traffic.

Create `/etc/systemd/system/songspot.service`:
```ini
[Unit]
Description=SongSpot ASGI Application
After=network.target

[Service]
User=root
WorkingDirectory=/var/www/songspot/songspot_backend
EnvironmentFile=/var/www/songspot/songspot_backend/.env
ExecStart=/var/www/songspot/songspot_backend/.venv/bin/daphne \
    -b 127.0.0.1 \
    -p 8000 \
    songspot.asgi:application
Restart=always

[Install]
WantedBy=multi-user.target
```

For future production log aggregation with Grafana Cloud on a non-Docker VPS, see [GRAFANA_SETUP.md](/Users/ethan/Personal/SongSpot/docs/GRAFANA_SETUP.md). The recommended direction is:
- keep app services on `systemd`
- log backend and catalogue jobs to `journald`
- ship only selected logs with Grafana Alloy
- keep Sentry for exceptions

```bash
sudo systemctl daemon-reload
sudo systemctl enable songspot
sudo systemctl start songspot
```

---

## 6. Static Files

Add to `settings.py`:
```python
STATIC_ROOT = '/var/www/songspot/static/'
```

```bash
cd /var/www/songspot/songspot_backend
source .venv/bin/activate
python manage.py collectstatic
```

---

## 7. Admin Brute Force Protection (django-axes)

django-axes is already configured in `settings.py`. After deploying, run migrations to create the axes tables:

```bash
python manage.py migrate
```

**Behavior:** 5 failed login attempts → 1-hour lockout. Resets automatically on successful login.

**If you lock yourself out:**
```bash
python manage.py axes_reset                    # reset all lockouts
python manage.py axes_reset --username yourname  # reset specific user
```

---

## 9. Security Settings

Add to `settings.py`:
```python
if not DEBUG:
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    SECURE_CONTENT_TYPE_NOSNIFF = True
    SECURE_HSTS_SECONDS = 31536000
    SECURE_HSTS_INCLUDE_SUBDOMAINS = True
    SECURE_HSTS_PRELOAD = True

CSRF_TRUSTED_ORIGINS = os.environ.get('CSRF_TRUSTED_ORIGINS', '').split(',')
```

> Note: `SECURE_SSL_REDIRECT` is omitted because Nginx already handles HTTP -> HTTPS redirection.

---

## 10. Firewall

```bash
sudo ufw allow 'Nginx Full'
sudo ufw allow OpenSSH
sudo ufw enable
```

---

## 11. Catalogue Data

The catalogue refills itself from Deezer; there is no offline seed list any
more. `seed_curated_artists` and `seed_curated_playlists` were one-shot
commands and have been replaced by `refresh_catalog`, which runs on a timer
(section 12) so a category is never a frozen snapshot of its seeding day.

```bash
cd /var/www/songspot/songspot_backend
source .venv/bin/activate

python manage.py refresh_catalog                  # every category
python manage.py refresh_catalog --category pop   # just one
python manage.py refresh_catalog --replace        # rebuild instead of add
python manage.py refresh_catalog --dry-run        # report, change nothing

python manage.py crawl_artists                    # widen along Deezer's artist graph
python manage.py add_artist "Artist Name"         # add a single artist on demand
```

Two one-shots worth knowing about, both safe to re-run:

```bash
python manage.py link_legacy_artists     # give seeded tracks a Deezer artist id
python manage.py backfill_artist_pictures  # fill artwork missing on `artists`
```

Never run two catalogue commands at once: they share one Deezer rate limit and
will simply starve each other.

---

## 12. Catalogue Timers

Three `systemd` timers keep the pools current. The unit files live in the repo
at `scripts/systemd/`.

```bash
cd /var/www/songspot
sudo cp scripts/systemd/songspot-*.service scripts/systemd/songspot-*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now songspot-refresh-catalog.timer \
                            songspot-rebuild-catalog.timer \
                            songspot-crawl-artists.timer
systemctl list-timers 'songspot-*'
```

| Timer | Schedule (server time) | What it does |
|---|---|---|
| `songspot-refresh-catalog` | daily 04:30 | `refresh_catalog --stale-only` — adds new releases |
| `songspot-crawl-artists` | daily 05:30 | walks Deezer's artist graph for the long tail |
| `songspot-rebuild-catalog` | Sunday 03:30 | `refresh_catalog --replace` — the only thing that evicts |

The weekly rebuild is not optional. A run without `--replace` has no eviction at
all, so a pool is otherwise a permanent accumulation of everything ever imported
into it, including rows from sources that have since been retired.

The schedules are deliberately an hour apart so two jobs never compete for the
same Deezer quota. `OnCalendar` is server local time — check `timedatectl`; a
VPS on UTC is two hours behind Paris in summer.

> A `Persistent=true` timer with no stamp file can fire the moment it is
> enabled. If that is not wanted on a loaded machine, create the stamps first:
> `sudo touch /var/lib/systemd/timers/stamp-songspot-refresh-catalog.timer`
> (and the same for the other two) before `enable --now`.

---

## 13. Monitoring

### UptimeRobot (server uptime)

1. Create a free account at [uptimerobot.com](https://uptimerobot.com)
2. Click **Add New Monitor**:
   - Type: `HTTP(s)`
   - Friendly Name: `SongSpot API`
   - URL: `https://api.yourdomain.com/health/` (or any always-available endpoint)
   - Monitoring Interval: `5 minutes`
3. Add alert contact (email) — you'll be notified within 5 minutes of downtime

No code changes needed. Fully external.

### Sentry (error tracking)

See full setup guide: [docs/SENTRY_SETUP.md](SENTRY_SETUP.md)

**Quick summary:**
- Create a free account at [sentry.io](https://sentry.io)
- Create two projects: `songspot-backend` (Django) and `songspot-mobile` (Flutter)
- Add `SENTRY_DSN` to your `.env` — Sentry only activates when `DEBUG=False`
- Set up alert rules in the Sentry dashboard for new issues and high-frequency errors

---

## 15. Production `.env` Reference

```env
# Django
DJANGO_SECRET_KEY=your-very-long-random-secret-key-here
DEBUG=False
# Keep the bare IP for older app versions that connect directly to it.
# Once all users have updated, you can remove the IP.
ALLOWED_HOSTS=api.yourdomain.com,YOUR_VPS_IP

# Database
DATABASE_URL=postgres://songspot_user:password@localhost:5432/songspot

# Channels (Redis-backed websocket fan-out)
USE_REDIS_CHANNEL_LAYER=True
CHANNEL_LAYERS_REDIS_URL=redis://localhost:6379/1

# Security
CSRF_TRUSTED_ORIGINS=https://api.yourdomain.com

# AdMob app-ads.txt (required for AdMob app verification)
APP_ADS_TXT=google.com, pub-2260442058102246, DIRECT, f08c47fec0942fa0

# Firebase Cloud Messaging (pick one)
# FCM_SERVICE_ACCOUNT_PATH=/var/www/songspot/secrets/firebase-service-account.json
# FCM_SERVICE_ACCOUNT_JSON={"type":"service_account", ...}

# Sentry (error monitoring) — only active when DEBUG=False
SENTRY_DSN=https://your-key@sentry.io/project-id
SENTRY_ENVIRONMENT=production
APP_VERSION=1.0.0
```

Generate a secret key:
```bash
python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"
```

---

## 16. Automatic Deploy from GitHub

The repo includes `.github/workflows/backend-deploy.yml` which deploys automatically when `main` is pushed with changes to `songspot_backend/**`, `docker-compose.yml`, or `scripts/deploy_backend.sh`.

### GitHub Secrets Required

Set in `Settings -> Secrets and variables -> Actions`:

| Secret | Required | Description |
|--------|----------|-------------|
| `VPS_SSH_PRIVATE_KEY` | Yes | SSH private key for the VPS |
| `VPS_HOST` | Yes | VPS hostname or IP |
| `VPS_USER` | Yes | SSH username (e.g. `root`) |
| `VPS_APP_DIR` | Yes | Repo path on VPS (e.g. `/var/www/songspot`) |
| `VPS_PORT` | No | SSH port (default: `22`) |
| `VPS_HOST_KEY` | No | Pinned host key for `known_hosts` |
| `VPS_DEPLOY_SCRIPT` | No | Deploy script path (default: `scripts/deploy_backend.sh`) |

### VPS Requirements

1. Clone the repo on the VPS at `VPS_APP_DIR`
2. Ensure `main` tracks the remote correctly
3. Ensure the VPS user can run:
   - `sudo -n systemctl restart songspot`

The deploy script (`scripts/deploy_backend.sh`) runs:
- `pip install -r requirements.txt`
- `python manage.py migrate --noinput`
- `python manage.py collectstatic --noinput`
- Restarts the `songspot` service

---

## 17. Mobile App Configuration

Update `songspot_mobile/.env`:
```env
API_BASE_URL=https://api.yourdomain.com
WS_BASE_URL=wss://api.yourdomain.com/ws
```

---

## 18. AdMob app-ads.txt Verification

SongSpot backend exposes:

- `GET https://api.yourdomain.com/app-ads.txt`

This value is controlled by `APP_ADS_TXT` in backend `.env`.

Verify after deploy:

```bash
curl -I https://api.yourdomain.com/app-ads.txt
curl https://api.yourdomain.com/app-ads.txt
```

Expected body:

```txt
google.com, pub-2260442058102246, DIRECT, f08c47fec0942fa0
```

For AdMob, make sure your app store listing website domain matches the same domain hosting `app-ads.txt`.

---

## Useful Commands

```bash
# Service status
sudo systemctl status songspot
sudo systemctl status nginx
systemctl list-timers 'songspot-*'

# Logs
sudo journalctl -u songspot -f
sudo journalctl -u songspot-refresh-catalog -f

# Restart everything
sudo systemctl restart songspot nginx

# Django management
cd /var/www/songspot/songspot_backend
source .venv/bin/activate
python manage.py migrate
python manage.py createsuperuser
```

---

## Deployment Checklist

- [ ] PostgreSQL installed, database and user created
- [ ] `.env` configured with all production values
- [ ] Django migrations run
- [ ] Catalogue populated (`refresh_catalog`), every category non-empty
- [ ] Redis installed and running
- [ ] Daphne service running (`songspot.service`)
- [ ] Catalogue timers enabled (`systemctl list-timers 'songspot-*'`)
- [ ] Nginx configured with SSL
- [ ] Static files collected
- [ ] Firewall configured (UFW)
- [ ] GitHub secrets configured for CI/CD
- [ ] Mobile app `.env` updated with production URL
- [ ] DNS `A` record for `api.yourdomain.com` pointing to VPS IP
- [ ] `https://api.yourdomain.com/app-ads.txt` is reachable and returns the expected publisher line
- [ ] UptimeRobot monitor created for `api.yourdomain.com`
- [ ] Sentry DSN configured in `.env` (backend + mobile)
- [ ] django-axes migrations run (admin brute force protection active)
