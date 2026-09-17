#!/usr/bin/env bash
# May be sent over SSH stdin. No live checkout is changed before writers stop.
set -euo pipefail
umask 077

ROOT_DIR="${1:-${DEPLOY_ROOT:-}}"
if [ -z "$ROOT_DIR" ]; then
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
ROOT_DIR="$(cd "$ROOT_DIR" && pwd -P)"
DEPLOY_REVISION="${2:-${DEPLOY_REVISION:-}}"
BACKEND_DIR="${BACKEND_DIR:-$ROOT_DIR/songspot_backend}"
BACKEND_DIR="$(cd "$BACKEND_DIR" && pwd -P)"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
BACKEND_SERVICE_NAME="${BACKEND_SERVICE_NAME:-songspot}"
JOB_WAIT_SECONDS="${JOB_WAIT_SECONDS:-300}"
VERIFY_DELAY_SECONDS="${VERIFY_DELAY_SECONDS:-2}"
[[ "$BACKEND_SERVICE_NAME" =~ ^[a-zA-Z0-9_.@-]+$ ]]
[[ "$JOB_WAIT_SECONDS" =~ ^[0-9]+$ && "$VERIFY_DELAY_SECONDS" =~ ^[0-9]+$ ]]
if [ "${RESTART_BACKEND_SERVICE:-true}" != true ]; then
  echo '[deploy] This deployment requires stopping and starting the backend.' >&2
  exit 1
fi
for command in git flock systemctl pg_dump pg_restore; do
  command -v "$command" >/dev/null
done
as_root() {
  if [ "$EUID" -eq 0 ]; then "$@"; else sudo -n "$@"; fi
}
as_root true

mkdir -p "$ROOT_DIR/.deploy"
chmod 700 "$ROOT_DIR/.deploy"
exec 9>"$ROOT_DIR/.deploy/backend.lock"
flock -n 9 || { echo '[deploy] Another deployment owns the lock.' >&2; exit 1; }
STATE_DIR="$(mktemp -d "$ROOT_DIR/.deploy/run-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")"
echo "[deploy] Recovery files: $STATE_DIR"

VENV_PATH="${VENV_PATH:-}"
if [ -z "$VENV_PATH" ]; then
  for candidate in "$BACKEND_DIR/.venv" "$ROOT_DIR/.venv" "$ROOT_DIR/venv" "$BACKEND_DIR/venv"; do
    if [ -x "$candidate/bin/python" ]; then VENV_PATH="$candidate"; break; fi
  done
fi
[ -n "$VENV_PATH" ] && [ -x "$VENV_PATH/bin/python" ] || {
  echo '[deploy] Existing Python virtualenv required.' >&2; exit 1;
}
VENV_PATH="$(cd "$VENV_PATH" && pwd -P)"
PYTHON="$VENV_PATH/bin/python"

cd "$ROOT_DIR"
git rev-parse HEAD > "$STATE_DIR/previous-revision"
if [ -n "$DEPLOY_REVISION" ]; then
  [[ "$DEPLOY_REVISION" =~ ^[a-fA-F0-9]{40}$ ]] || { echo '[deploy] Expected a full commit SHA.' >&2; exit 1; }
  git fetch --prune origin main
  [ "$(git branch --show-current)" = main ] || { echo '[deploy] VPS checkout must be on main.' >&2; exit 1; }
  git diff --quiet && git diff --cached --quiet || { echo '[deploy] Tracked local changes on VPS; refusing to overwrite.' >&2; exit 1; }
  git merge-base --is-ancestor "$DEPLOY_REVISION" origin/main || { echo "[deploy] Target commit is not on origin/main." >&2; exit 1; }
  git merge-base --is-ancestor HEAD "$DEPLOY_REVISION" || { echo "[deploy] Refusing an older or divergent commit." >&2; exit 1; }
  git show "$DEPLOY_REVISION:scripts/deploy_support.py" > "$STATE_DIR/deploy_support.py"
  git show "$DEPLOY_REVISION:scripts/systemd/songspot-search-worker.service" > "$STATE_DIR/worker.template"
else
  cp "$ROOT_DIR/scripts/deploy_support.py" "$STATE_DIR/deploy_support.py"
  cp "$ROOT_DIR/scripts/systemd/songspot-search-worker.service" "$STATE_DIR/worker.template"
fi
printf '%s\n' "${DEPLOY_REVISION:-working-tree}" > "$STATE_DIR/target-revision"
SUPPORT=("$PYTHON" "$STATE_DIR/deploy_support.py" --root "$ROOT_DIR" --backend "$BACKEND_DIR" --venv "$VENV_PATH" --state "$STATE_DIR" --systemd "$SYSTEMD_DIR" --service "$BACKEND_SERVICE_NAME" --enrichment "${DEPLOY_SEARCH_ENRICHMENT_ENABLED:-}")
"${SUPPORT[@]}" preflight
[ "$(systemctl show -p LoadState --value "$BACKEND_SERVICE_NAME.service")" = loaded ] || {
  echo '[deploy] Backend systemd unit not found.' >&2; exit 1;
}
SERVICE_USER="$(systemctl show -p User --value "$BACKEND_SERVICE_NAME.service")"
SERVICE_USER="${SERVICE_USER:-root}"

# A failed backup leaves the running application untouched. No retention purge.
"${SUPPORT[@]}" backup

TIMERS=()
MAINTENANCE=0
SUCCEEDED=0
cleanup() {
  local status=$?
  trap - EXIT
  if [ "$SUCCEEDED" -ne 1 ]; then
    if [ "$MAINTENANCE" -eq 1 ]; then
      as_root systemctl stop songspot-crawl-artists.timer songspot-refresh-catalog.timer songspot-rebuild-catalog.timer || true
      as_root systemctl stop "$BACKEND_SERVICE_NAME.service" songspot-search-worker.service songspot-crawl-artists.service songspot-refresh-catalog.service songspot-rebuild-catalog.service || true
      echo "[deploy] FAILED: backend/worker/timers remain stopped. Repair and rerun; recovery files: $STATE_DIR" >&2
    else
      for timer in "${TIMERS[@]}"; do as_root systemctl start "$timer" || true; done
      echo '[deploy] FAILED before code/schema changes; running backend preserved.' >&2
    fi
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

for job in songspot-crawl-artists songspot-refresh-catalog songspot-rebuild-catalog; do
  if [ "$(systemctl show -p LoadState --value "$job.timer")" = loaded ]; then
    if systemctl is-active --quiet "$job.timer"; then TIMERS+=("$job.timer"); fi
    as_root systemctl stop "$job.timer"
  fi
done
printf '%s\n' "${TIMERS[@]}" > "$STATE_DIR/active-timers"
deadline=$((SECONDS + JOB_WAIT_SECONDS))
while :; do
  busy=0
  for job in songspot-crawl-artists songspot-refresh-catalog songspot-rebuild-catalog; do
    state="$(systemctl show -p ActiveState --value "$job.service")"
    case "$state" in active|activating|deactivating) busy=1 ;; esac
  done
  [ "$busy" -eq 1 ] || break
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo '[deploy] An import is still running. Retry after it finishes.' >&2
    exit 1
  fi
  echo '[deploy] Waiting for existing catalogue imports...'
  sleep 2
done

MAINTENANCE=1
as_root systemctl stop "$BACKEND_SERVICE_NAME.service"
if [ "$(systemctl show -p LoadState --value songspot-search-worker.service)" = loaded ]; then
  as_root systemctl stop songspot-search-worker.service
fi
if [ -n "$DEPLOY_REVISION" ]; then
  git merge --ff-only "$DEPLOY_REVISION"
fi
cd "$BACKEND_DIR"
if [ -n "${PRE_DEPLOY_CMD:-}" ]; then bash -lc "$PRE_DEPLOY_CMD"; fi
"$PYTHON" -m pip install -r requirements.txt

export SEARCH_BACKEND=postgres SEARCH_INDEX_ENABLED=False
# A busy DDL lock fails instead of waiting indefinitely. No statement timeout
# on the bounded backfill, whose first pass covers the whole catalogue.
PGOPTIONS="${PGOPTIONS:-} -c lock_timeout=5s" "$PYTHON" manage.py migrate --noinput
PGOPTIONS="${PGOPTIONS:-} -c lock_timeout=5s" "$PYTHON" manage.py search_backfill
ENRICHMENT="$(as_root "${SUPPORT[@]}" configure --service-user "$SERVICE_USER")"
export SEARCH_ENRICHMENT_ENABLED="$ENRICHMENT"
"$PYTHON" manage.py collectstatic --noinput
"$PYTHON" manage.py check
# Only local housekeeping here, even when enrichment will be enabled at startup.
SEARCH_ENRICHMENT_ENABLED=False "$PYTHON" manage.py search_worker --once
"$PYTHON" manage.py search_health

as_root systemctl daemon-reload
as_root systemctl enable songspot-search-worker.service
as_root systemctl start "$BACKEND_SERVICE_NAME.service"
as_root systemctl start songspot-search-worker.service
sleep "$VERIFY_DELAY_SECONDS"
systemctl is-active --quiet "$BACKEND_SERVICE_NAME.service"
systemctl is-active --quiet songspot-search-worker.service
if [ -n "${POST_DEPLOY_CMD:-}" ]; then bash -lc "$POST_DEPLOY_CMD"; fi
for timer in "${TIMERS[@]}"; do as_root systemctl start "$timer"; done
SUCCEEDED=1
printf '%s\n' ready > "$STATE_DIR/status"
echo "[deploy] Backend ready: PostgreSQL only; enrichment=$ENRICHMENT"
