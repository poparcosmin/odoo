#!/bin/bash
# generate-secrets.sh — generează secrete random pentru .env
#
# Output: imprimă pe stdout 4 linii ready-to-copy în .env (sau --update direct).
#
# Usage:
#   scripts/generate-secrets.sh                # print only
#   scripts/generate-secrets.sh --update       # update .env in place (cu backup)
#   scripts/generate-secrets.sh --update --force  # skip confirmation prompt

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"
UPDATE=0
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --update) UPDATE=1 ;;
    --force)  FORCE=1 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
  esac
done

generate() {
  openssl rand -base64 32 | tr -d '\n=' | head -c 32
}

DB_PASSWORD=$(generate)
MASTER_PASSWORD=$(generate)
BACKUP_KEY=$(generate)
WEBHOOK_SECRET=$(generate)

cat <<SECRETS
ODOO_DB_PASSWORD=${DB_PASSWORD}
ODOO_MASTER_PASSWORD=${MASTER_PASSWORD}
BACKUP_ENCRYPTION_KEY=${BACKUP_KEY}
MEDUSA_WEBHOOK_SECRET=${WEBHOOK_SECRET}
SECRETS

if [[ $UPDATE -eq 0 ]]; then
  echo "[generate-secrets] (--update absent: doar print, .env neschimbat)" >&2
  exit 0
fi

#─────────────────────────────────────────────────────────────────────────
# Update .env în place
#─────────────────────────────────────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Run cp config/env.template .env first." >&2
  exit 1
fi

if [[ $FORCE -eq 0 ]]; then
  echo >&2
  read -rp "[generate-secrets] Replace 4 secrets în .env? [yes/no] " confirm
  [[ "$confirm" == "yes" ]] || { echo "Aborted."; exit 0; }
fi

cp "$ENV_FILE" "${ENV_FILE}.bak.$(date +%s)"
echo "[generate-secrets] Backup: ${ENV_FILE}.bak.*" >&2

# Replace 4 keys (preserving order + comments)
sed -i \
  -e "s|^ODOO_DB_PASSWORD=.*|ODOO_DB_PASSWORD=${DB_PASSWORD}|" \
  -e "s|^ODOO_MASTER_PASSWORD=.*|ODOO_MASTER_PASSWORD=${MASTER_PASSWORD}|" \
  -e "s|^BACKUP_ENCRYPTION_KEY=.*|BACKUP_ENCRYPTION_KEY=${BACKUP_KEY}|" \
  -e "s|^MEDUSA_WEBHOOK_SECRET=.*|MEDUSA_WEBHOOK_SECRET=${WEBHOOK_SECRET}|" \
  "$ENV_FILE"

echo "[generate-secrets] ✓ .env updated. Restart container pentru a aplica:" >&2
echo "  docker compose restart" >&2
