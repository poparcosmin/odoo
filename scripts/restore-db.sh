#!/bin/bash
# restore-db.sh — restore complet Odoo (PostgreSQL + filestore).
#
# CRITICAL: restore PG fără filestore = facturi PDF rupte.
# Acest script restaurează AMBELE atomic.
#
# Usage:
#   scripts/restore-db.sh <backup_path> <target_db_name>
#
# Exemplu:
#   scripts/restore-db.sh data/backup/daily/paff_prod-20260501-080000 paff_test

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILESTORE_ROOT="${REPO_ROOT}/data/filestore"

BACKUP_PATH="${1:-}"
TARGET_DB="${2:-}"

if [[ -z "$BACKUP_PATH" || -z "$TARGET_DB" ]]; then
  echo "Usage: $0 <backup_path> <target_db_name>" >&2
  exit 1
fi

if [[ ! -d "$BACKUP_PATH" ]]; then
  echo "ERROR: backup not found: $BACKUP_PATH" >&2
  exit 1
fi

if [[ ! -f "${BACKUP_PATH}/db.dump" ]]; then
  echo "ERROR: db.dump missing in backup" >&2
  exit 1
fi

cat "${BACKUP_PATH}/MANIFEST" 2>/dev/null || true
echo
echo "═══════════════════════════════════════════════════════════════"
echo "  RESTORE TARGET: $TARGET_DB"
echo "  Source:         $BACKUP_PATH"
echo "═══════════════════════════════════════════════════════════════"
echo "  ⚠ Acest restore VA SUPRASCRIE DB '$TARGET_DB' dacă există."
echo "  ⚠ Toate sesiunile active ale Odoo vor fi întrerupte."
echo

read -rp "Confirmă RESTORE (tastează exact numele DB-ului '$TARGET_DB'): " confirm
if [[ "$confirm" != "$TARGET_DB" ]]; then
  echo "Aborted: confirmation mismatch."
  exit 1
fi

#─────────────────────────────────────────────────────────────────────────
# Step 1: Drop & recreate target DB
#─────────────────────────────────────────────────────────────────────────
echo "[restore] Step 1/3: drop & recreate $TARGET_DB ..."
docker exec paff-erp-postgres \
  psql --username="${PG_USER:-odoo_user}" \
       --dbname=postgres \
       -c "DROP DATABASE IF EXISTS \"$TARGET_DB\";"
docker exec paff-erp-postgres \
  psql --username="${PG_USER:-odoo_user}" \
       --dbname=postgres \
       -c "CREATE DATABASE \"$TARGET_DB\" WITH OWNER \"${PG_USER:-odoo_user}\";"

#─────────────────────────────────────────────────────────────────────────
# Step 2: pg_restore
#─────────────────────────────────────────────────────────────────────────
echo "[restore] Step 2/3: pg_restore ..."
docker exec -i paff-erp-postgres \
  pg_restore --username="${PG_USER:-odoo_user}" \
             --dbname="$TARGET_DB" \
             --no-owner --no-acl \
  < "${BACKUP_PATH}/db.dump"

#─────────────────────────────────────────────────────────────────────────
# Step 3: Filestore restore
#─────────────────────────────────────────────────────────────────────────
if [[ -f "${BACKUP_PATH}/filestore.tar.gz" ]]; then
  echo "[restore] Step 3/3: filestore restore (via docker exec, scratch dir) ..."
  ORIG_DB=$(awk '/^db_name:/ {print $2}' "${BACKUP_PATH}/MANIFEST")
  SCRATCH_DIR="/tmp/restore-filestore-$$"

  # CRITICAL: cleanup ONLY target. NU șterge ORIG_DB (poate fi acelaşi Docker
  # stack ca prod live). Bug fix 2026-05-07.
  docker exec paff-erp-odoo \
    rm -rf "/var/lib/odoo/filestore/${TARGET_DB}"

  # Untar în SCRATCH dir izolat (NU peste /var/lib/odoo/filestore real)
  docker exec paff-erp-odoo mkdir -p "$SCRATCH_DIR"
  docker exec -i paff-erp-odoo \
    tar xzf - -C "$SCRATCH_DIR" \
    < "${BACKUP_PATH}/filestore.tar.gz"

  # Move din scratch (mereu numit ORIG_DB în tar) la target
  docker exec paff-erp-odoo \
    mv "${SCRATCH_DIR}/${ORIG_DB}" "/var/lib/odoo/filestore/${TARGET_DB}"
  if [[ "$ORIG_DB" != "$TARGET_DB" ]]; then
    echo "[restore]   Filestore copied scratch → ${TARGET_DB} (orig=${ORIG_DB} preserved)"
  fi

  # Cleanup scratch dir
  docker exec paff-erp-odoo rm -rf "$SCRATCH_DIR"
elif [[ -f "${BACKUP_PATH}/.no-filestore" ]]; then
  echo "[restore] Step 3/3: skipped (backup had no filestore)"
else
  echo "[restore] ⚠ No filestore.tar.gz in backup. Attachments will be MISSING."
fi

echo "[restore] ✓ Restore complete: $TARGET_DB"
echo "[restore] Next: docker compose restart odoo && check /web/login"
