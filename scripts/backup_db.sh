#!/usr/bin/env bash
#
# Nightly logical backup of the SongSpot database.
#
# Local only. This protects against a bad migration, a wrong DELETE or a
# dropped table — not against losing the VPS, since the dumps sit on the same
# disk as the cluster. An off-site copy is still missing; see
# docs/DEPLOYMENT_GUIDE.md.
#
# A dump that has never been read back is not a backup, so every run parses its
# own output with `pg_restore -l` and fails loudly if that does not work.

set -euo pipefail

DB_NAME="${DB_NAME:-songspot}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/songspot}"
KEEP_DAYS="${KEEP_DAYS:-14}"

STAMP="$(date +%Y%m%d-%H%M%S)"
TARGET="${BACKUP_DIR}/${DB_NAME}-${STAMP}.dump"

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

# pg_dump runs as `postgres`, which cannot write into a root-owned 700
# directory, so it writes to a temp file it owns and root moves it into place.
TMP="$(mktemp -u /tmp/songspot-dump-XXXXXX.dump)"

echo "[backup] dumping ${DB_NAME}"
sudo -u postgres pg_dump -Fc -d "${DB_NAME}" -f "${TMP}"
mv "${TMP}" "${TARGET}"
chown root:root "${TARGET}"
chmod 600 "${TARGET}"

# Verify before rotating: a corrupt dump must never cause a good one to be
# deleted.
echo "[backup] verifying"
ENTRIES="$(pg_restore -l "${TARGET}" | grep -c . )"
if [ "${ENTRIES}" -lt 50 ]; then
  echo "[backup] FAILED: ${TARGET} only lists ${ENTRIES} entries" >&2
  exit 1
fi

SIZE="$(du -h "${TARGET}" | cut -f1)"
echo "[backup] ok: ${TARGET} (${SIZE}, ${ENTRIES} entries)"

echo "[backup] pruning dumps older than ${KEEP_DAYS} days"
find "${BACKUP_DIR}" -maxdepth 1 -name "${DB_NAME}-*.dump" -mtime "+${KEEP_DAYS}" -print -delete

REMAINING="$(find "${BACKUP_DIR}" -maxdepth 1 -name "${DB_NAME}-*.dump" | wc -l)"
TOTAL="$(du -sh "${BACKUP_DIR}" | cut -f1)"
echo "[backup] ${REMAINING} dumps retained, ${TOTAL} total"
