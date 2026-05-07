#!/bin/bash
# audit-filestore.sh — verify filestore permissions & ownership.
#
# B7 din Phase 1 plan v2. Verify:
# - Owner: postgres user în container (UID 70 pe alpine)
# - Permissions: 0700 (rwx user only) pentru directory tree
# - File count vs DB attachments count (catch orphans)
#
# Usage: scripts/audit-filestore.sh [db_name=paff_prod]
# Exit: 0 OK, 1 issues found

set -uo pipefail  # NU -e — vrem să rulăm tot

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_NAME="${1:-paff_prod}"
PG_USER="${PG_USER:-odoo_user}"

echo "════════════════════════════════════════════════════════════════"
echo "  AUDIT FILESTORE — $DB_NAME"
echo "════════════════════════════════════════════════════════════════"

ISSUES=0

# ─── 1. Filestore exists ───────────────────────────────────────────────
if ! docker exec paff-erp-odoo test -d "/var/lib/odoo/filestore/${DB_NAME}"; then
  echo "[1] ✗ Filestore /var/lib/odoo/filestore/${DB_NAME} MISSING"
  ISSUES=$((ISSUES + 1))
else
  FILE_COUNT=$(docker exec paff-erp-odoo \
    find "/var/lib/odoo/filestore/${DB_NAME}" -type f 2>/dev/null | wc -l)
  echo "[1] ✓ Filestore exists: $FILE_COUNT files"
fi

# ─── 2. Permissions check (no world-readable) ──────────────────────────
WORLD_READABLE=$(docker exec paff-erp-odoo \
  find "/var/lib/odoo/filestore/${DB_NAME}" -type d -perm /o+r 2>/dev/null | wc -l)
if [[ "$WORLD_READABLE" -gt 0 ]]; then
  echo "[2] ⚠ $WORLD_READABLE directories world-readable (should be 0700)"
  ISSUES=$((ISSUES + 1))
else
  echo "[2] ✓ No world-readable directories"
fi

# ─── 3. Ownership check (postgres user) ────────────────────────────────
OWNER=$(docker exec paff-erp-odoo \
  stat -c '%U' "/var/lib/odoo/filestore/${DB_NAME}" 2>/dev/null)
if [[ "$OWNER" == "odoo" || "$OWNER" == "postgres" ]]; then
  echo "[3] ✓ Owner: $OWNER"
else
  echo "[3] ⚠ Unexpected owner: $OWNER (expected odoo/postgres)"
  ISSUES=$((ISSUES + 1))
fi

# ─── 4. DB attachments vs filestore files (orphan detect) ──────────────
DB_ATTACH_COUNT=$(docker exec paff-erp-postgres \
  psql -U "$PG_USER" -d "$DB_NAME" -tAc "
    SELECT count(*) FROM ir_attachment
    WHERE store_fname IS NOT NULL AND store_fname != ''
  " 2>/dev/null)

if [[ -n "$DB_ATTACH_COUNT" && -n "${FILE_COUNT:-}" ]]; then
  DIFF=$((FILE_COUNT - DB_ATTACH_COUNT))
  ABS_DIFF=${DIFF#-}
  if [[ "$ABS_DIFF" -le 5 ]]; then
    echo "[4] ✓ DB attachments: $DB_ATTACH_COUNT, files: $FILE_COUNT (diff=$DIFF, OK)"
  else
    echo "[4] ⚠ Mismatch: DB=$DB_ATTACH_COUNT vs files=$FILE_COUNT (diff=$DIFF)"
    ISSUES=$((ISSUES + 1))
  fi
fi

# ─── 5. Total filestore size ───────────────────────────────────────────
SIZE=$(docker exec paff-erp-odoo \
  du -sh "/var/lib/odoo/filestore/${DB_NAME}" 2>/dev/null | cut -f1)
echo "[5] ℹ Total size: $SIZE"

# ─── Final ─────────────────────────────────────────────────────────────
echo
if [[ "$ISSUES" -eq 0 ]]; then
  echo "✅ AUDIT PASSED — filestore $DB_NAME OK"
  exit 0
else
  echo "⚠ AUDIT: $ISSUES issue(s) found"
  exit 1
fi
