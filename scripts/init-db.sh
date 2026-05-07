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

# MODULE MT940 (l10n_ro_account_bank_statement_import_mt940_*) cer dependența
# `account_statement_import_file` care e în OCA/bank-statement-import (alt submodule).
# Pentru a le activa, adaugă mai întâi:
#   git submodule add https://github.com/OCA/bank-statement-import.git src/addons-vendor/bank-statement-import
# Apoi adaugă "l10n_ro_account_bank_statement_import_mt940_{base,bcr,ing}" în lista de mai sus.

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

# ODOO_RC env în container e setat la /etc/odoo/odoo.conf (template).
# Override la /tmp/odoo.conf.rendered (envsubst-ed de entrypoint).
docker exec -e ODOO_RC=/tmp/odoo.conf.rendered paff-erp-odoo \
  odoo \
    -d "$DB_NAME" \
    --init "$MODULES_CSV" \
    --load-language ro_RO \
    $DEMO_FLAG \
    --stop-after-init \
    --log-level=info

#─────────────────────────────────────────────────────────────────────────
# POST-INIT: Blacklist module Website (PAFF e pure ERP).
#
# Storefront-ul e Medusa la paff.ro. Odoo nu trebuie să facă duplicate.
# Decizie documentată în docs/adr/0003-pure-erp-no-website.md.
#
# Setăm auto_install=False ca să prevenim re-instalare accidentală prin:
#   - Apps page → Update Module List → Install (user click)
#   - Dependency cascade când instalez addon nou care declară `depends: ['website']`
#
# Module afectate: website + 4 children + viitoare website_*.
# Lista: query directă cu LIKE 'website%' (acoperă auto-discovery future modules).
#─────────────────────────────────────────────────────────────────────────
echo "[init-db] Blacklist module Website (PAFF pure ERP, see ADR 0003)..."

docker exec paff-erp-postgres \
  psql -U "${ODOO_DB_USER}" -d "$DB_NAME" -q -c "
    UPDATE ir_module_module
    SET auto_install = false
    WHERE name LIKE 'website%'
       OR name LIKE 'theme_%'
       OR name IN ('mass_mailing', 'survey');
  " > /dev/null

WEBSITE_BLACKLISTED=$(docker exec paff-erp-postgres \
  psql -U "${ODOO_DB_USER}" -d "$DB_NAME" -tAc \
    "SELECT count(*) FROM ir_module_module WHERE name LIKE 'website%' AND auto_install = false")

echo "[init-db]   → ${WEBSITE_BLACKLISTED} module website* marcate auto_install=false"

#─────────────────────────────────────────────────────────────────────────
# POST-INIT: Phase 2 Batch A — payment terms + export rights + activities
# (zero-credit business model + PAFF activity types)
#─────────────────────────────────────────────────────────────────────────
PHASE2A_SCRIPT="${REPO_ROOT}/scripts/phase-2-batch-a-quick-wins.py"
if [[ -f "$PHASE2A_SCRIPT" ]]; then
  echo "[init-db] Apply Phase 2 Batch A (payment terms, export rights, activities)..."
  docker cp "$PHASE2A_SCRIPT" paff-erp-odoo:/tmp/phase2_batch_a.py
  docker exec -e ODOO_RC=/tmp/odoo.conf.rendered -i paff-erp-odoo \
    odoo shell -d "$DB_NAME" --no-http \
    < "$PHASE2A_SCRIPT" 2>&1 | grep -E "^\[E|^\[T|✅|→ |^E[0-9]|^T[0-9]" || true
  echo "[init-db]   ✓ Phase 2 Batch A applied"
fi

echo
echo "[init-db] ✓ DB '$DB_NAME' initialized cu localizare RO"
echo "[init-db] Login: admin / admin (SCHIMBĂ parola IMEDIAT prin /web/login)"
echo
echo "[init-db] Browser: http://localhost:8310/web/login"
echo "[init-db]          → login admin/admin → /odoo backend"
echo
echo "[init-db] NOTĂ: NU expunem /web/database/manager în prod (security risk)."
echo "[init-db]       În dev e accesibil dar nu îl folosi pentru creare DB —"
echo "[init-db]       use scripts/init-db.sh pentru reproducibilitate."
