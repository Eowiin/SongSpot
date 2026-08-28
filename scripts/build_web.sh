#!/usr/bin/env bash

# Builds the Flutter web client and, optionally, publishes it to a web root.
#
#   ./scripts/build_web.sh                       # build only
#   WEB_ROOT=/var/www/songspot-web ./scripts/build_web.sh
#
# The web build reads its API host from songspot_mobile/.env at build time,
# exactly like the mobile builds, so point that file at the right backend
# before running this.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE_DIR="${MOBILE_DIR:-$ROOT_DIR/songspot_mobile}"
BASE_HREF="${BASE_HREF:-/}"

if [ ! -d "${MOBILE_DIR}" ]; then
  echo "Flutter project not found: ${MOBILE_DIR}" >&2
  exit 1
fi

if [ ! -f "${MOBILE_DIR}/.env" ]; then
  echo "Missing ${MOBILE_DIR}/.env — the build bundles it as an asset." >&2
  echo "Copy .env.example and set API_BASE_URL to your backend." >&2
  exit 1
fi

cd "${MOBILE_DIR}"

echo "[web] API_BASE_URL: $(grep -E '^API_BASE_URL=' .env || echo '(not set — will default to localhost)')"

echo "[web] Installing dependencies"
flutter pub get

echo "[web] Building release bundle (base-href ${BASE_HREF})"
flutter build web --release --base-href "${BASE_HREF}"

BUILD_DIR="${MOBILE_DIR}/build/web"
echo "[web] Built ${BUILD_DIR}"

if [ -n "${WEB_ROOT:-}" ]; then
  echo "[web] Publishing to ${WEB_ROOT}"
  mkdir -p "${WEB_ROOT}"
  # --delete drops files from previous builds (hashed CanvasKit assets etc.)
  rsync -a --delete "${BUILD_DIR}/" "${WEB_ROOT}/"
  echo "[web] Published"
fi

echo "[web] Done"
