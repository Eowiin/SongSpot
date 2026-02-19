# SongSpot Deployment Guide

Guide for deploying SongSpot to a VPS with PostgreSQL, HTTPS, and proper environment configuration.

---

## 1. PostgreSQL Setup

### Install PostgreSQL on VPS

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install postgresql postgresql-contrib

# Start and enable
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

### Create Database and User

```bash
sudo -u postgres psql

# In PostgreSQL shell:
CREATE DATABASE songspot;
CREATE USER songspot_user WITH PASSWORD 'your_secure_password_here';
ALTER ROLE songspot_user SET client_encoding TO 'utf8';
ALTER ROLE songspot_user SET default_transaction_isolation TO 'read committed';
ALTER ROLE songspot_user SET timezone TO 'UTC';
GRANT ALL PRIVILEGES ON DATABASE songspot TO songspot_user;
\q
```

### Update Django Settings

Add to `requirements.txt`:
```
psycopg2-binary==2.9.9
```

Update `.env`:
```env
DATABASE_URL=postgres://songspot_user:your_secure_password_here@localhost:5432/songspot
```

Update `songspot/settings.py`:
```python
import dj_database_url

# Replace the DATABASES section with:
DATABASES = {
    'default': dj_database_url.config(
        default=os.environ.get('DATABASE_URL'),
        conn_max_age=600,
        conn_health_checks=True,
    )
}

# Fallback for local development
if not os.environ.get('DATABASE_URL'):
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.sqlite3',
            'NAME': BASE_DIR / 'db.sqlite3',
        }
    }
```

Add to `requirements.txt`:
```
dj-database-url==2.1.0
```

### Run Migrations

```bash
python manage.py migrate
python manage.py createsuperuser
python manage.py fetch_deezer_tracks  # Populate tracks
```

---

## 2. Redis + Celery (Stem Generation)

### Install Redis

```bash
sudo apt install redis-server
sudo systemctl enable redis-server
sudo systemctl start redis-server
```

### Configure Celery Env Vars

Add to your `.env`:
```env
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0
```

### Run Celery Worker (systemd)

Create a service file (example: `/etc/systemd/system/songspot-celery.service`):
```ini
[Unit]
Description=SongSpot Celery Worker
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/path/to/BlindTest-friends/songspot_backend
EnvironmentFile=/path/to/BlindTest-friends/songspot_backend/.env
ExecStart=/path/to/BlindTest-friends/.venv/bin/celery -A songspot worker -l info
Restart=always

[Install]
WantedBy=multi-user.target
```

Then enable and start:
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
sudo certbot --nginx -d your-domain.com -d api.your-domain.com
```

### Auto-Renewal

```bash
# Test renewal
sudo certbot renew --dry-run

# Certbot auto-adds a cron job, verify with:
sudo systemctl status certbot.timer
```

---

## 4. Nginx Configuration

### Install Nginx

```bash
sudo apt install nginx
```

### Create Site Config

```bash
sudo nano /etc/nginx/sites-available/songspot
```

```nginx
upstream asgi {
    server 127.0.0.1:8000;
}

server {
    listen 80;
    server_name your-domain.com api.your-domain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com api.your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        proxy_pass http://asgi;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket endpoint for real-time chat
    location /ws/ {
        proxy_pass http://asgi;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 86400;
    }

    location /static/ {
        alias /var/www/songspot/static/;
    }
}
```

### Enable Site

```bash
sudo ln -s /etc/nginx/sites-available/songspot /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

---

## 4. Environment Configuration

### Production `.env` File

```env
# Django
DJANGO_SECRET_KEY=your-very-long-random-secret-key-here
DEBUG=False
ALLOWED_HOSTS=your-domain.com,api.your-domain.com

# Database
DATABASE_URL=postgres://songspot_user:password@localhost:5432/songspot

# Stems cleanup (hours)
STEM_TTL_HOURS=72

# Channels (Redis-backed websocket fan-out)
USE_REDIS_CHANNEL_LAYER=True
CHANNEL_LAYERS_REDIS_URL=redis://localhost:6379/1

# Firebase Cloud Messaging
# FCM_SERVICE_ACCOUNT_PATH=/var/www/songspot/secrets/firebase-service-account.json
# OR
# FCM_SERVICE_ACCOUNT_JSON={"type":"service_account", ...}
```

---

## 5. Stems Pipeline (Demucs)

### Install Demucs
```bash
pip install demucs
```

### Generate Stems (Batch)
```bash
python manage.py generate_pack_stems --all --missing-only
```

### Cleanup Old Stems
```bash
python manage.py cleanup_stems --max-age-hours 72
```

### Serve Media (Stems)
For production, serve `/media/` via Nginx:
```nginx
location /media/ {
    alias /var/www/songspot/media/;
}
```

Make sure `MEDIA_ROOT` points to the same directory in your Django settings.

---

## 6. Daily UTC Jobs (Single VPS with Cron)

Run a daily job to preselect daily songs and daily pack tracks, and generate stems:
```bash
0 0 * * * cd /path/to/BlindTest-friends/songspot_backend && /path/to/venv/bin/python manage.py prepare_daily_content --generate-stems >> /var/log/songspot_daily.log 2>&1
```

Optional cleanup job:
```bash
0 3 * * * cd /path/to/BlindTest-friends/songspot_backend && /path/to/venv/bin/python manage.py cleanup_stems --max-age-hours 72 >> /var/log/songspot_cleanup.log 2>&1
```

---

## 7. Seed Data (Option A)

Populate tracks and create 3 genre packs:
```bash
python manage.py fetch_deezer_tracks --count 200
python manage.py seed_genre_packs --count-per-pack 30 --genres pop,rock,hiphop
```

# Security
CSRF_TRUSTED_ORIGINS=https://your-domain.com,https://api.your-domain.com

# Deezer API (if using app credentials)
DEEZER_APP_ID=your_app_id
DEEZER_APP_SECRET=your_app_secret
```

### Generate Secret Key

```bash
python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"
```

### Update Settings for Production

Add to `songspot/settings.py`:

```python
# Security settings for production
if not DEBUG:
    SECURE_SSL_REDIRECT = True
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    SECURE_BROWSER_XSS_FILTER = True
    SECURE_CONTENT_TYPE_NOSNIFF = True
    SECURE_HSTS_SECONDS = 31536000  # 1 year
    SECURE_HSTS_INCLUDE_SUBDOMAINS = True
    SECURE_HSTS_PRELOAD = True

# CSRF trusted origins
CSRF_TRUSTED_ORIGINS = os.environ.get('CSRF_TRUSTED_ORIGINS', '').split(',')
```

---

## 5. ASGI Server Setup (HTTP + WebSocket)

Use one ASGI server (Daphne) for both REST and websocket traffic.

```bash
sudo nano /etc/systemd/system/songspot.service
```

```ini
[Unit]
Description=SongSpot ASGI Application
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/var/www/songspot/songspot_backend
Environment="PATH=/var/www/songspot/venv/bin"
EnvironmentFile=/var/www/songspot/songspot_backend/.env
ExecStart=/var/www/songspot/venv/bin/daphne \
    -b 127.0.0.1 \
    -p 8000 \
    songspot.asgi:application
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
sudo mkdir -p /var/log/songspot
sudo chown www-data:www-data /var/log/songspot
sudo systemctl daemon-reload
sudo systemctl start songspot
sudo systemctl enable songspot
```

---

## 7. Static Files

```bash
# Collect static files
python manage.py collectstatic

# Set permissions
sudo chown -R www-data:www-data /var/www/songspot/static/
```

Add to `settings.py`:
```python
STATIC_ROOT = '/var/www/songspot/static/'
```

---

## 8. Firewall Setup

```bash
sudo ufw allow 'Nginx Full'
sudo ufw allow OpenSSH
sudo ufw enable
```

---

## 9. Mobile App Configuration

Update `songspot_mobile/.env`:
```env
API_BASE_URL=https://api.your-domain.com
WS_BASE_URL=wss://api.your-domain.com/ws
```

---

## Quick Deployment Checklist

- [ ] PostgreSQL installed and configured
- [ ] Database created with user permissions
- [ ] Django migrations run
- [ ] Tracks populated (`fetch_deezer_tracks`)
- [ ] Nginx installed and configured
- [ ] SSL certificate obtained (Let's Encrypt)
- [ ] Gunicorn service running
- [ ] Daphne service running (for WebSockets)
- [ ] Static files collected
- [ ] Firewall configured
- [ ] Environment variables set (DEBUG=False)
- [ ] Mobile app API URL updated

---

## Useful Commands

```bash
# Check service status
sudo systemctl status songspot
sudo systemctl status songspot-ws
sudo systemctl status nginx

# View logs
sudo journalctl -u songspot -f
sudo tail -f /var/log/songspot/error.log

# Restart services
sudo systemctl restart songspot songspot-ws nginx

# Django management
cd /var/www/songspot/songspot_backend
source ../venv/bin/activate
python manage.py migrate
python manage.py createsuperuser
```
