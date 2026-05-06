#!/bin/bash
# PAFF Odoo healthcheck — verifică /web/health endpoint.
# Folosit de Docker HEALTHCHECK directive în Dockerfile.

set -euo pipefail

ODOO_PORT="${ODOO_HTTP_PORT:-8069}"
HEALTH_URL="http://localhost:${ODOO_PORT}/web/health"

response=$(curl -sf --max-time 5 "$HEALTH_URL" 2>&1) || {
  echo "[healthcheck] FAIL: $HEALTH_URL unreachable" >&2
  exit 1
}

if [[ "$response" != *'"status": "pass"'* ]] && [[ "$response" != *'"status":"pass"'* ]]; then
  echo "[healthcheck] FAIL: unexpected response: $response" >&2
  exit 1
fi

exit 0
