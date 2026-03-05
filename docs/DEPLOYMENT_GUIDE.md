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

## 2. Redis + Celery

### Install Redis

```bash
sudo apt install redis-server
sudo systemctl enable redis-server
sudo systemctl start redis-server
```

### Configure Env Vars

Add to `.env`:
```env
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0
USE_REDIS_CHANNEL_LAYER=True
CHANNEL_LAYERS_REDIS_URL=redis://localhost:6379/1
```

### Celery Worker (systemd)

Create `/etc/systemd/system/songspot-celery.service`:
```ini
[Unit]
Description=SongSpot Celery Worker
After=network.target redis-server.service

[Service]
Type=forking
User=root
WorkingDirectory=/var/www/songspot/songspot_backend
EnvironmentFile=/var/www/songspot/songspot_backend/.env
ExecStart=/var/www/songspot/songspot_backend/.venv/bin/celery \
    -A songspot multi start worker \
    --pidfile=/var/run/celery/%n.pid \
    --logfile=/var/log/celery/%n%%I.log \
    --loglevel=info
ExecStop=/var/www/songspot/songspot_backend/.venv/bin/celery \
    -A songspot multi stopwait worker \
    --pidfile=/var/run/celery/%n.pid
ExecReload=/var/www/songspot/songspot_backend/.venv/bin/celery \
    -A songspot multi restart worker \
    --pidfile=/var/run/celery/%n.pid \
    --logfile=/var/log/celery/%n%%I.log \
    --loglevel=info
Restart=on-failure
RuntimeDirectory=celery
LogsDirectory=celery

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable songspot-celery
sudo systemctl start songspot-celery
```

---

## 3. HTTPS with Let's Encrypt

### Install Certbot

```bash
sudo apt install certbot python3-certbot-nginx
```

### Get SSL Certificate

```bash
sudo certbot --nginx -d your-domain.com
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

Create `/etc/nginx/sites-available/songspot`:
```nginx
upstream asgi {
    server 127.0.0.1:8000;
}

server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

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

    # Media files (stems)
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

## 11. Seed Data

```bash
cd /var/www/songspot/songspot_backend
source .venv/bin/activate
python manage.py fetch_deezer_tracks --count 200
python manage.py seed_genre_packs --count-per-pack 30 --genres pop,rock,hiphop
```

---

## 12. Stems Pipeline (Demucs)

### Generate Stems (Batch)
```bash
python manage.py generate_pack_stems --all --missing-only
```

### Cleanup Old Stems
```bash
python manage.py cleanup_stems --max-age-hours 72
```

---

## 13. Daily Cron Jobs (Required)

**These cron jobs are required for the app to function properly.** Add them with `crontab -e`:

### Daily song preparation (noon UTC)

Creates today's `DailySong` for every room and triggers push notifications to all users.
Stems are generated on-demand when users start playing (not pre-generated).

```bash
0 12 * * * cd /var/www/songspot/songspot_backend && /var/www/songspot/songspot_backend/.venv/bin/python manage.py prepare_daily_content >> /var/log/songspot_daily.log 2>&1
```

### Cleanup old stems (3 AM UTC)

```bash
0 3 * * * cd /var/www/songspot/songspot_backend && /var/www/songspot/songspot_backend/.venv/bin/python manage.py cleanup_stems --max-age-hours 72 >> /var/log/songspot_cleanup.log 2>&1
```

---

## 14. Monitoring

### UptimeRobot (server uptime)

1. Create a free account at [uptimerobot.com](https://uptimerobot.com)
2. Click **Add New Monitor**:
   - Type: `HTTP(s)`
   - Friendly Name: `SongSpot API`
   - URL: `https://your-domain.com/health/` (or any always-available endpoint)
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
ALLOWED_HOSTS=your-domain.com

# Database
DATABASE_URL=postgres://songspot_user:password@localhost:5432/songspot

# Celery
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0

# Channels (Redis-backed websocket fan-out)
USE_REDIS_CHANNEL_LAYER=True
CHANNEL_LAYERS_REDIS_URL=redis://localhost:6379/1

# Stems cleanup (hours)
STEM_TTL_HOURS=72

# Security
CSRF_TRUSTED_ORIGINS=https://your-domain.com

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
   - `sudo -n systemctl restart songspot-celery`

The deploy script (`scripts/deploy_backend.sh`) runs:
- `pip install -r requirements.txt`
- `python manage.py migrate --noinput`
- `python manage.py collectstatic --noinput`
- Restarts `songspot` and `songspot-celery` services

---

## 17. Mobile App Configuration

Update `songspot_mobile/.env`:
```env
API_BASE_URL=https://your-domain.com
WS_BASE_URL=wss://your-domain.com/ws
```

---

## 18. AdMob app-ads.txt Verification

SongSpot backend exposes:

- `GET https://your-domain.com/app-ads.txt`

This value is controlled by `APP_ADS_TXT` in backend `.env`.

Verify after deploy:

```bash
curl -I https://your-domain.com/app-ads.txt
curl https://your-domain.com/app-ads.txt
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
sudo systemctl status songspot-celery
sudo systemctl status nginx

# Logs
sudo journalctl -u songspot -f
sudo journalctl -u songspot-celery -f

# Restart everything
sudo systemctl restart songspot songspot-celery nginx

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
- [ ] Tracks populated (`fetch_deezer_tracks`)
- [ ] Redis installed and running
- [ ] Daphne service running (`songspot.service`)
- [ ] Celery worker running (`songspot-celery.service`)
- [ ] Nginx configured with SSL
- [ ] Static files collected
- [ ] Firewall configured (UFW)
- [ ] Cron jobs set up (daily content + stem cleanup)
- [ ] GitHub secrets configured for CI/CD
- [ ] Mobile app `.env` updated with production URL
- [ ] `https://your-domain.com/app-ads.txt` is reachable and returns the expected publisher line
- [ ] UptimeRobot monitor created for the domain
- [ ] Sentry DSN configured in `.env` (backend + mobile)
- [ ] django-axes migrations run (admin brute force protection active)
