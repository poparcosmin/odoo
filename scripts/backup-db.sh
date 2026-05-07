#!/bin/bash
# backup-db.sh — backup complet Odoo (PostgreSQL + filestore).
#
# CRITICAL: Filestore-ul (attachment-uri PDF/imagini) NU e în PG.
# Backup PG-only = pierdere date. Acest script face AMBELE.
#
# Layout: docs/adr/0001-three-layer-isolation.md, secțiunea "Backup"
#
# Usage:
#   scripts/backup-db.sh <db_name>
#   scripts/backup-db.sh <db_name> --type weekly
#   scripts/backup-db.sh paff_prod --type monthly

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_ROOT="${REPO_ROOT}/data/backup"
FILESTORE_ROOT="${REPO_ROOT}/data/filestore"

DB_NAME="${1:-}"
BACKUP_TYPE="${2:-daily}"

if [[ -z "$DB_NAME" ]]; then
  echo "Usage: $0 <db_name> [--type daily|weekly|monthly]" >&2
  exit 1
fi

# GFS retention policy:
#   daily   — 7 backups (1 săptămână)
#   weekly  — 4 backups (1 lună)
#   monthly — 60 backups (5 ani — minim legal RO pentru date fiscale)
case "$BACKUP_TYPE" in
  daily)   RETENTION=7  ;;
  weekly)  RETENTION=4  ;;
  monthly) RETENTION=60 ;;
  *) echo "Invalid type: $BACKUP_TYPE" >&2; exit 1 ;;
esac

DEST_DIR="${BACKUP_ROOT}/${BACKUP_TYPE}"
mkdir -p "$DEST_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="${DB_NAME}-${TIMESTAMP}"
BACKUP_PATH="${DEST_DIR}/${BACKUP_NAME}"
mkdir -p "$BACKUP_PATH"

echo "[backup] Starting ${BACKUP_TYPE} backup of $DB_NAME → $BACKUP_PATH"

#─────────────────────────────────────────────────────────────────────────
# Step 1: PostgreSQL dump
#─────────────────────────────────────────────────────────────────────────
echo "[backup] Step 1/3: pg_dump ..."
docker exec paff-erp-postgres \
  pg_dump --format=custom --no-owner --no-acl \
          --username="${PG_USER:-odoo_user}" \
          --dbname="$DB_NAME" \
  > "${BACKUP_PATH}/db.dump"

DB_SIZE=$(du -sh "${BACKUP_PATH}/db.dump" | cut -f1)
echo "[backup]   PG dump: $DB_SIZE"

#─────────────────────────────────────────────────────────────────────────
# Step 2: Filestore tar (attachments — NU sunt în PG)
# Filestore-ul e în container Odoo (volume named, NU bind mount pe host).
#─────────────────────────────────────────────────────────────────────────
FILESTORE_EXISTS=$(docker exec paff-erp-odoo \
  test -d "/var/lib/odoo/filestore/${DB_NAME}" && echo "yes" || echo "no")

if [[ "$FILESTORE_EXISTS" == "yes" ]]; then
  echo "[backup] Step 2/3: tar filestore (via docker exec) ..."
  docker exec paff-erp-odoo \
    tar czf - -C /var/lib/odoo/filestore "$DB_NAME" \
    > "${BACKUP_PATH}/filestore.tar.gz"
  FS_SIZE=$(du -sh "${BACKUP_PATH}/filestore.tar.gz" | cut -f1)
  echo "[backup]   Filestore: $FS_SIZE"
else
  echo "[backup]   ⚠ No filestore directory in container (new DB?)"
  touch "${BACKUP_PATH}/.no-filestore"
fi

#─────────────────────────────────────────────────────────────────────────
# Step 3: Manifest + checksums
#─────────────────────────────────────────────────────────────────────────
echo "[backup] Step 3/3: manifest + checksums ..."
cat > "${BACKUP_PATH}/MANIFEST" <<EOF
db_name: $DB_NAME
backup_type: $BACKUP_TYPE
timestamp: $TIMESTAMP
odoo_version: $(awk -F= '/^ARG ODOO_VERSION=/ {print $2}' "${REPO_ROOT}/docker/Dockerfile")
created_by: $(whoami)@$(hostname)
EOF

cd "$BACKUP_PATH"
sha256sum db.dump filestore.tar.gz 2>/dev/null > checksums.sha256 || true
cd - >/dev/null

#─────────────────────────────────────────────────────────────────────────
# Retention: șterge backup-uri vechi peste limit
#─────────────────────────────────────────────────────────────────────────
echo "[backup] Applying GFS retention ($BACKUP_TYPE → keep last $RETENTION)..."
ls -1tr "$DEST_DIR" \
  | grep "^${DB_NAME}-" \
  | head -n "-${RETENTION}" \
  | while read -r old; do
      echo "[backup]   Pruning: $old"
      rm -rf "${DEST_DIR:?}/${old}"
    done

echo "[backup] ✓ Done: $BACKUP_PATH"
