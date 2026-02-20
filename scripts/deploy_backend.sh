#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="${BACKEND_DIR:-$ROOT_DIR/songspot_backend}"

if [ ! -d "${BACKEND_DIR}" ]; then
  echo "Backend directory does not exist: ${BACKEND_DIR}" >&2
  exit 1
fi

if [ -n "${PRE_DEPLOY_CMD:-}" ]; then
  echo "[deploy] Running PRE_DEPLOY_CMD"
  bash -lc "${PRE_DEPLOY_CMD}"
fi

resolve_venv_path() {
  local candidate

  for candidate in \
    "${BACKEND_DIR}/.venv" \
    "${ROOT_DIR}/.venv" \
    "${ROOT_DIR}/venv" \
    "${BACKEND_DIR}/venv"; do
    if [ -f "${candidate}/bin/activate" ]; then
      echo "${candidate}"
      return 0
    fi
  done

  return 1
}

VENV_PATH="${VENV_PATH:-}"
if [ -z "${VENV_PATH}" ]; then
  VENV_PATH="$(resolve_venv_path || true)"
fi

if [ -z "${VENV_PATH}" ] || [ ! -f "${VENV_PATH}/bin/activate" ]; then
  echo "Python virtualenv not found. Set VENV_PATH to your venv directory." >&2
  exit 1
fi

cd "${BACKEND_DIR}"
# shellcheck disable=SC1090
source "${VENV_PATH}/bin/activate"

echo "[deploy] Installing dependencies"
pip install -r requirements.txt

echo "[deploy] Running migrations"
python manage.py migrate --noinput

echo "[deploy] Collecting static files"
python manage.py collectstatic --noinput

restart_service() {
  local service_name="$1"
  local should_restart="$2"

  if [ "${should_restart}" != "true" ]; then
    return 0
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    echo "[deploy] systemctl is unavailable. Skipping ${service_name} restart."
    return 0
  fi

  if ! systemctl list-unit-files --type=service --no-legend | awk '{print $1}' | grep -qx "${service_name}.service"; then
    echo "[deploy] ${service_name}.service not found. Skipping restart."
    return 0
  fi

  echo "[deploy] Restarting ${service_name}.service"
  sudo -n systemctl restart "${service_name}"
}

restart_service "${BACKEND_SERVICE_NAME:-songspot}" "${RESTART_BACKEND_SERVICE:-true}"
restart_service "${CELERY_SERVICE_NAME:-songspot-celery}" "${RESTART_CELERY_SERVICE:-true}"

if [ -n "${POST_DEPLOY_CMD:-}" ]; then
  echo "[deploy] Running POST_DEPLOY_CMD"
  bash -lc "${POST_DEPLOY_CMD}"
fi

echo "[deploy] Backend deployment completed"
