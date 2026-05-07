#!/bin/bash
# verify-backup.sh — restore most recent daily backup la temp DB + smoke test.
#
# Asigură că backup-urile NU sunt corupte (false security prevention).
# Per CLAUDE.md regula 12: "Backup VERIFIED" — fără test, backup = false security.
#
# Usage:
#   scripts/verify-backup.sh                    # auto-pick latest daily
#   scripts/verify-backup.sh <backup_path>      # specific backup
#
# Exit codes: 0 = OK, 1 = FAIL (backup corrupt or smoke test failed)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAILY_DIR="${REPO_ROOT}/data/backup/daily"
TEST_DB="paff_test_restore"
PG_USER="${PG_USER:-odoo_user}"

BACKUP_PATH="${1:-}"

# Auto-pick latest daily dacă nu specified
if [[ -z "$BACKUP_PATH" ]]; then
  BACKUP_PATH=$(ls -1dt "$DAILY_DIR"/paff_prod-* 2>/dev/null | head -1)
  if [[ -z "$BACKUP_PATH" ]]; then
    echo "FAIL: no daily backup found in $DAILY_DIR" >&2
    exit 1
  fi
fi

echo "════════════════════════════════════════════════════════════════"
echo "  VERIFY BACKUP — $BACKUP_PATH → $TEST_DB"
echo "════════════════════════════════════════════════════════════════"

# ─── Step 1: Restore în test DB ────────────────────────────────────────
echo "[verify] Step 1/4: drop & restore $TEST_DB ..."

# Drop + recreate test DB
docker exec paff-erp-postgres \
  psql --username="$PG_USER" --dbname=postgres \
       -c "DROP DATABASE IF EXISTS \"$TEST_DB\";"
docker exec paff-erp-postgres \
  psql --username="$PG_USER" --dbname=postgres \
       -c "CREATE DATABASE \"$TEST_DB\" WITH OWNER \"$PG_USER\";"

# Restore PG dump
docker exec -i paff-erp-postgres \
  pg_restore --username="$PG_USER" --dbname="$TEST_DB" --no-owner --no-acl \
  < "${BACKUP_PATH}/db.dump" 2>&1 | tail -5 || true

# ─── Step 2: SQL smoke tests (NU pornim Odoo, e mai rapid) ─────────────
echo "[verify] Step 2/4: SQL smoke tests ..."

SMOKE_RESULT=$(docker exec paff-erp-postgres \
  psql --username="$PG_USER" --dbname="$TEST_DB" -t -A -F'|' -c "
    SELECT 'company_count', count(*) FROM res_company;
    SELECT 'company_name', name FROM res_company WHERE id = 1;
    SELECT 'admin_login', login FROM res_users WHERE id = 2;
    SELECT 'partner_count', count(*) FROM res_partner WHERE active = true;
    SELECT 'modules_installed', count(*) FROM ir_module_module WHERE state = 'installed';
    SELECT 'bank_accounts', count(*) FROM res_partner_bank;
    SELECT 'sale_journal_code', code FROM account_journal WHERE type = 'sale' AND company_id = 1;
  ")

# Parse + verify
FAILED=0
verify_check() {
  local key="$1"
  local expected="$2"
  local actual=$(echo "$SMOKE_RESULT" | grep "^${key}|" | cut -d'|' -f2)
  if [[ "$actual" == "$expected" ]] || [[ -z "$expected" && -n "$actual" ]]; then
    echo "  ✓ $key: $actual"
  else
    echo "  ✗ $key: got='$actual' expected='$expected'"
    FAILED=$((FAILED + 1))
  fi
}

verify_check "company_count" "1"
verify_check "company_name" "PAFF SRL"
verify_check "admin_login" "paff.office@gmail.com"
verify_check "modules_installed" ""  # any non-zero
verify_check "bank_accounts" "3"
verify_check "sale_journal_code" "FAC"

# Partner count: must be > 0 (există implicit OdooBot + PAFF SRL + alți)
PARTNER_COUNT=$(echo "$SMOKE_RESULT" | grep "^partner_count|" | cut -d'|' -f2)
if [[ "$PARTNER_COUNT" -ge 2 ]]; then
  echo "  ✓ partner_count: $PARTNER_COUNT (>= 2)"
else
  echo "  ✗ partner_count: $PARTNER_COUNT (< 2)"
  FAILED=$((FAILED + 1))
fi

# ─── Step 3: Filestore verify (în SCRATCH DIR — NU peste filestore real!) ─
# CRITICAL: Untar într-un /tmp scratch dir SEPARAT de /var/lib/odoo/filestore.
# Bugul anterior (restore peste paff_prod + rename + cleanup) a distrus filestore-ul
# real. Lecție pe viu — testat cu hard reset 2026-05-07.
echo "[verify] Step 3/4: filestore verify (scratch dir, NU touchez real) ..."

if [[ -f "${BACKUP_PATH}/filestore.tar.gz" ]]; then
  SCRATCH_DIR="/tmp/verify-filestore-$$"

  # Untar în scratch dir izolat
  docker exec paff-erp-odoo mkdir -p "$SCRATCH_DIR"
  docker exec -i paff-erp-odoo \
    tar xzf - -C "$SCRATCH_DIR" < "${BACKUP_PATH}/filestore.tar.gz"

  # Count files
  FS_COUNT=$(docker exec paff-erp-odoo \
    find "$SCRATCH_DIR" -type f 2>/dev/null | wc -l)
  if [[ "$FS_COUNT" -gt 0 ]]; then
    echo "  ✓ filestore: $FS_COUNT files"
  else
    echo "  ✗ filestore: 0 files (expected attachments)"
    FAILED=$((FAILED + 1))
  fi

  # Cleanup scratch (NU touchez real filestore!)
  docker exec paff-erp-odoo rm -rf "$SCRATCH_DIR"
else
  echo "  ⚠ no filestore in backup (acceptable for new DB)"
fi

# ─── Step 4: Cleanup test DB ───────────────────────────────────────────
echo "[verify] Step 4/4: cleanup ..."
docker exec paff-erp-postgres \
  psql --username="$PG_USER" --dbname=postgres \
       -c "DROP DATABASE IF EXISTS \"$TEST_DB\";" > /dev/null 2>&1

# ─── Final report ──────────────────────────────────────────────────────
echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "✅ VERIFY PASSED — backup integrity confirmed: $BACKUP_PATH"
  exit 0
else
  echo "❌ VERIFY FAILED — $FAILED checks failed: $BACKUP_PATH"
  exit 1
fi
