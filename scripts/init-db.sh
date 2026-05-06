#!/bin/bash
# init-db.sh — initialize PAFF Odoo database with Romanian localization.
#
# Usage:
#   scripts/init-db.sh                          # creates DB cu name din .env
#   scripts/init-db.sh paff_test                # creates DB paff_test
#   scripts/init-db.sh paff_test --demo         # cu demo data (dev only)
#
# Requirements:
#   - docker compose up -d (postgres + odoo running)
#   - .env populat (ODOO_DB_NAME, ODOO_DB_USER, etc.)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_NAME="${1:-${ODOO_DB_NAME:-paff_prod}}"
WITH_DEMO=0

for arg in "$@"; do
  case "$arg" in
    --demo) WITH_DEMO=1 ;;
  esac
done

# Source .env pentru DB credentials
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a; source "${REPO_ROOT}/.env"; set +a
else
  echo "ERROR: .env not found. Run: cp config/env.template .env" >&2
  exit 1
fi

#─────────────────────────────────────────────────────────────────────────
# Module-uri l10n_ro de instalat default (DECIZIA 2 din plan: A = toate).
#
# Cele 18 documentate în Ecommerce monorepo (testate pentru B2B PAFF).
# OCA expune 29 module total — vezi ls src/addons-vendor/l10n-romania/
# pentru lista completă. Adaugă/scoate aici după nevoie.
#─────────────────────────────────────────────────────────────────────────
DEFAULT_L10N_RO_MODULES=(
  # Account / fiscal
  "l10n_ro_account"
  "l10n_ro_account_report_invoice"
  "l10n_ro_fiscal_validation"
  "l10n_ro_vat_on_payment"
  # Bank statements MT940
  "l10n_ro_account_bank_statement_import_mt940_base"
  "l10n_ro_account_bank_statement_import_mt940_bcr"
  "l10n_ro_account_bank_statement_import_mt940_ing"
  # Geo / partners
  "l10n_ro_city"
  "l10n_ro_partner_create_by_vat"
  "l10n_ro_partner_unique"
  # Config
  "l10n_ro_config"
  # SPV / e-Factura
  "l10n_ro_message_spv"
  # Stock
  "l10n_ro_stock"
  "l10n_ro_stock_account"
  "l10n_ro_stock_account_landed_cost"
  # Payments
  "l10n_ro_payment_receipt_report"
  "l10n_ro_payment_to_statement"
)

MODULES_CSV=$(IFS=','; echo "${DEFAULT_L10N_RO_MODULES[*]}")

echo "[init-db] ─── Initialize Romanian Odoo DB ─────────────────────"
echo "[init-db] DB:       $DB_NAME"
echo "[init-db] Locale:   ro_RO.UTF-8"
echo "[init-db] Modules:  ${#DEFAULT_L10N_RO_MODULES[@]} l10n_ro_*"
echo "[init-db] Demo:     $([ $WITH_DEMO -eq 1 ] && echo 'YES (dev)' || echo 'NO')"
echo

# Verify Odoo container running
if ! docker ps --format '{{.Names}}' | grep -q '^paff-erp-odoo$'; then
  echo "ERROR: container paff-erp-odoo not running. Start cu: docker compose up -d" >&2
  exit 1
fi

# Verify DB doesn't exist already
DB_EXISTS=$(docker exec paff-erp-postgres \
  psql -U "${ODOO_DB_USER}" -tAc \
       "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" 2>/dev/null || echo "")

if [[ "$DB_EXISTS" == "1" ]]; then
  echo "ERROR: DB '$DB_NAME' already exists. Drop sau folosește alt nume." >&2
  echo "  Drop: docker exec paff-erp-postgres dropdb -U ${ODOO_DB_USER} ${DB_NAME}" >&2
  exit 1
fi

#─────────────────────────────────────────────────────────────────────────
# Init Odoo DB cu locale RO + l10n_ro_* modules
#─────────────────────────────────────────────────────────────────────────
DEMO_FLAG=""
if [[ $WITH_DEMO -eq 0 ]]; then
  DEMO_FLAG="--without-demo=all"
fi

echo "[init-db] Running odoo --init... (acest pas poate dura 5-10 minute)"

docker exec paff-erp-odoo \
  odoo \
    -c /etc/odoo/odoo.conf \
    -d "$DB_NAME" \
    --init "$MODULES_CSV" \
    --load-language ro_RO \
    $DEMO_FLAG \
    --stop-after-init \
    --log-level=info

echo
echo "[init-db] ✓ DB '$DB_NAME' initialized cu localizare RO"
echo "[init-db] Login: admin / admin (SCHIMBĂ parola IMEDIAT prin /web/login)"
echo
echo "[init-db] Browser: http://localhost:8310/web/database/manager"
echo "[init-db]          → click pe '$DB_NAME' → login admin/admin"
