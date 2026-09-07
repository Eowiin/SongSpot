# Grafana Cloud Logs Setup

Production-oriented guide for future log aggregation on a VPS running Nginx and `systemd` services.

This setup is intentionally narrow:
- Keep `Sentry` for exceptions and traces
- Use `Grafana Cloud` for backend and server logs
- Ship only the logs that matter first
- Avoid heavy local observability stacks on the VPS

This guide assumes:
- backend code lives at `/var/www/songspot/songspot_backend`
- backend runs as a `systemd` service (`songspot.service`)
- catalogue jobs run as `systemd` timers (`songspot-*.timer`)
- Nginx is installed directly on the VPS

---

## 1. What to Send

Start with these sources only:
- Django / Daphne service logs from `journald`
- catalogue timer logs from `journald` (`songspot-refresh-catalog`, etc.)
- Nginx `error.log`

Avoid shipping these on day one:
- full Nginx access logs
- debug-level app logs
- raw request bodies
- auth tokens, session cookies, JWTs, push tokens, receipts

Reason: this keeps VPS overhead low and avoids burning free log quota on noisy traffic.

---

## 2. Why This Setup

Use each tool for a different job:
- `Sentry`: exceptions, stack traces, release-linked failures
- `Grafana Cloud Logs`: searchable service and server logs
- `journald` + `logrotate`: local fallback retention on the VPS

Do not replace Sentry with Grafana logs. They solve different problems.

---

## 3. Create a Grafana Cloud Stack

1. Create a Grafana Cloud account: <https://grafana.com/products/cloud/>
2. Create a stack
3. Open the stack's log ingestion page
4. Copy:
   - Loki endpoint URL
   - username / instance ID
   - API token

You will use those values in the Alloy config below.

---

## 4. Install Grafana Alloy on the VPS

Grafana Alloy is the lightweight agent that reads local logs and pushes them to Grafana Cloud.

Follow the official install guide for your distro:
- <https://grafana.com/docs/alloy/latest/set-up/install/>

After install, Alloy usually runs as a `systemd` service named `alloy`.

Check:

```bash
sudo systemctl status alloy
```

---

## 5. Configure Backend Services to Log to Journald

Prefer `systemd` journal output over custom application log files.

For the SongSpot backend service, the simplest pattern is:

```ini
[Service]
WorkingDirectory=/var/www/songspot/songspot_backend
EnvironmentFile=/var/www/songspot/songspot_backend/.env
ExecStart=/var/www/songspot/songspot_backend/.venv/bin/daphne -b 127.0.0.1 -p 8000 songspot.asgi:application
Restart=always
StandardOutput=journal
StandardError=journal
SyslogIdentifier=songspot-backend
```

The catalogue timers are `Type=oneshot` and already log to `journald` without
extra configuration — see `scripts/systemd/`.

Why:
- easier to query with `journalctl`
- easier for Alloy to scrape
- avoids manual file management for app logs

Useful checks:

```bash
sudo journalctl -u songspot.service -n 100 --no-pager
sudo journalctl -u songspot-refresh-catalog.service -n 100 --no-pager
```

---

## 6. Minimal Alloy Config

Create or update `/etc/alloy/config.alloy` with a small log-only pipeline.

Replace these placeholders first:
- `GRAFANA_LOKI_URL`
- `GRAFANA_USERNAME`
- `GRAFANA_API_TOKEN`
- `YOUR_HOSTNAME`

```alloy
logging {
  level  = "info"
  format = "logfmt"
}

loki.write "grafana_cloud" {
  endpoint {
    url = "GRAFANA_LOKI_URL"
    basic_auth {
      username = "GRAFANA_USERNAME"
      password = "GRAFANA_API_TOKEN"
    }
  }
}

loki.source.journal "songspot_services" {
  matches = "_SYSTEMD_UNIT=songspot.service + _SYSTEMD_UNIT=songspot-refresh-catalog.service"
  labels = {
    job      = "systemd-journal",
    app      = "songspot",
    host     = "YOUR_HOSTNAME",
    env      = "production",
  }
  forward_to = [loki.write.grafana_cloud.receiver]
}

loki.source.file "nginx_error" {
  targets = [
    {
      __path__ = "/var/log/nginx/error.log",
      job      = "nginx-error",
      app      = "songspot",
      host     = "YOUR_HOSTNAME",
      env      = "production",
    },
  ]
  forward_to = [loki.write.grafana_cloud.receiver]
}
```

Then restart Alloy:

```bash
sudo systemctl restart alloy
sudo systemctl status alloy
```

If your Alloy package uses a different config path, keep the same content and adapt the location to your install.

Official references:
- <https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.journal/>
- <https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.file/>
- <https://grafana.com/docs/alloy/latest/reference/components/loki/loki.write/>

---

## 7. Keep Local Retention Too

Even with remote logs, keep local retention on the VPS.

Recommended:
- `journald` with a size cap
- `logrotate` for Nginx logs

Example `journald` limits in `/etc/systemd/journald.conf`:

```ini
[Journal]
SystemMaxUse=300M
RuntimeMaxUse=100M
MaxRetentionSec=14day
```

After changes:

```bash
sudo systemctl restart systemd-journald
```

Check current journal usage:

```bash
journalctl --disk-usage
```

For Nginx, Ubuntu/Debian usually already ships a `logrotate` config. Verify it exists:

```bash
cat /etc/logrotate.d/nginx
```

---

## 8. Recommended Django Logging Shape

Add a real Django `LOGGING` config before relying on Grafana for production logs.

Production goals:
- log to stdout only
- use structured fields when possible
- keep app logger level at `INFO`
- keep framework noise lower
- never log secrets

At minimum:
- `INFO` for important business events
- `WARNING` for degraded behavior
- `ERROR` / `exception` for failures
- `DEBUG` disabled in production

Do not log:
- JWTs
- full WebSocket URLs containing tokens
- passwords
- cookies
- payment receipts
- FCM device tokens

---

## 9. Correlate with Sentry

You do not need a deep integration between Grafana Cloud and Sentry to get value.

Keep them aligned with shared metadata:
- environment: `production`
- release: app/backend version
- service name: `songspot-backend`, `songspot-refresh-catalog`

That is enough to make incidents easier to trace across tools.

---

## 10. What to Add Later

Only add these once the basic setup is stable:
- Nginx access logs with filtering
- server metrics
- request IDs in Django logs
- alerts for repeated `5xx` or a catalogue timer exiting non-zero

Do not add everything at once. Start with the smallest useful pipeline.

---

## 11. Suggested Rollout Order

1. Keep Sentry enabled for backend and mobile
2. Move backend logs to `journald`
3. Add Django production logging config
4. Install Alloy
5. Ship backend, catalogue timer, and Nginx error logs only
6. Verify volume and retention in Grafana Cloud
7. Add metrics or access-log ingestion only if needed

---

## 12. Useful Commands

Local service inspection:

```bash
sudo systemctl status songspot.service
systemctl list-timers 'songspot-*'
sudo systemctl status nginx
sudo systemctl status alloy
```

Recent logs:

```bash
sudo journalctl -u songspot.service -n 100 --no-pager
sudo journalctl -u songspot-refresh-catalog.service -n 100 --no-pager
sudo tail -n 100 /var/log/nginx/error.log
```

---

## 13. Notes for SongSpot

Current code already uses Sentry, which should remain the primary exception-monitoring tool.

Before pushing more logs to production tools, clean up sensitive logging:
- mobile WebSocket connection logging currently risks exposing the tokenized URL
- backend logging should stay structured and avoid request secrets

This Grafana setup is intended as the next layer after Sentry, not a replacement for it.
