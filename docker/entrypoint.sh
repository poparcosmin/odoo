#!/bin/bash
# PAFF Odoo container entrypoint.
# Aplică patches/ peste sources Odoo înainte de start (Layer 2 din Three-Layer Isolation).
# Vezi: patches/README.md, docs/adr/0001-three-layer-isolation.md

set -euo pipefail

PATCH_DIR="/opt/paff-patches"
ODOO_SRC="/usr/lib/python3/dist-packages/odoo"
APPLIED_MARKER="/var/lib/odoo/.patches-applied"

apply_patches() {
  if [[ ! -d "$PATCH_DIR" ]] || [[ -z "$(ls -A "$PATCH_DIR"/*.patch 2>/dev/null)" ]]; then
    echo "[paff] No patches to apply."
    return 0
  fi

  if [[ -f "$APPLIED_MARKER" ]]; then
    echo "[paff] Patches already applied (marker: $APPLIED_MARKER)."
    return 0
  fi

  echo "[paff] Applying patches from $PATCH_DIR ..."
  cd "$ODOO_SRC"
  for patch in "$PATCH_DIR"/*.patch; do
    patch_name=$(basename "$patch")
    echo "[paff]   → $patch_name"
    if ! patch -p1 --dry-run --silent < "$patch"; then
      echo "[paff] ✗ Patch $patch_name fails dry-run. Aborting startup." >&2
      exit 1
    fi
    patch -p1 --silent < "$patch"
  done
  touch "$APPLIED_MARKER"
  echo "[paff] All patches applied successfully."
}

wait_for_postgres() {
  local host="${HOST:-postgres}"
  local port="${PORT:-5432}"
  local timeout=60
  local elapsed=0

  echo "[paff] Waiting for PostgreSQL at ${host}:${port}..."
  while ! (echo > /dev/tcp/${host}/${port}) 2>/dev/null; do
    sleep 2
    elapsed=$((elapsed + 2))
    if [[ $elapsed -ge $timeout ]]; then
      echo "[paff] ✗ PostgreSQL unreachable after ${timeout}s." >&2
      exit 1
    fi
  done
  echo "[paff] PostgreSQL ready."
}

render_odoo_conf() {
  local src="${ODOO_RC:-/etc/odoo/odoo.conf}"
  local rendered="/tmp/odoo.conf.rendered"

  if [[ ! -f "$src" ]]; then
    echo "[paff] WARNING: $src not found, skipping envsubst" >&2
    return 0
  fi

  # Default values pentru variabile lipsă (evităm Odoo crash pe ${VAR} literal)
  : "${ODOO_DB_HOST:=postgres}"
  : "${ODOO_DB_PORT:=5432}"
  : "${ODOO_DB_USER:=odoo_user}"
  : "${ODOO_DB_NAME:=paff_prod}"
  : "${ODOO_DB_PASSWORD:?ODOO_DB_PASSWORD must be set in .env}"
  : "${ODOO_MASTER_PASSWORD:?ODOO_MASTER_PASSWORD must be set in .env}"
  : "${ODOO_WORKERS:=0}"
  : "${ODOO_LIMIT_MEMORY_SOFT:=2147483648}"
  : "${ODOO_LIMIT_MEMORY_HARD:=2684354560}"
  : "${ODOO_LIMIT_TIME_CPU:=600}"
  : "${ODOO_LIMIT_TIME_REAL:=1200}"

  export ODOO_DB_HOST ODOO_DB_PORT ODOO_DB_USER ODOO_DB_NAME ODOO_DB_PASSWORD \
         ODOO_MASTER_PASSWORD ODOO_WORKERS \
         ODOO_LIMIT_MEMORY_SOFT ODOO_LIMIT_MEMORY_HARD \
         ODOO_LIMIT_TIME_CPU ODOO_LIMIT_TIME_REAL

  envsubst < "$src" > "$rendered"
  export ODOO_RC="$rendered"
  echo "[paff] Rendered config: $rendered (workers=$ODOO_WORKERS)"
}

apply_patches
render_odoo_conf
wait_for_postgres

exec "$@"
