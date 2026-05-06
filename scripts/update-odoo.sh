#!/bin/bash
# update-odoo.sh — actualizare controlată a imaginii Odoo upstream.
#
# Workflow:
#   1. Pull versiunea target (sau --latest-stable)
#   2. Extract digest SHA
#   3. Build staging container cu noua versiune
#   4. Smoke test (vezi secțiunea TODO la final)
#   5. Diff Dockerfile cu noua versiune + digest
#   6. Prompt confirmare
#   7. Update Dockerfile + commit
#
# Usage:
#   scripts/update-odoo.sh --target 19.0-20260601
#   scripts/update-odoo.sh --latest-stable
#   scripts/update-odoo.sh --dry-run --target 19.0-20260601

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="${REPO_ROOT}/docker/Dockerfile"
STAGING_TAG="paff-odoo:staging"
STAGING_CONTAINER="paff-odoo-staging-update"

TARGET=""
DRY_RUN=0
LATEST_STABLE=0

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)         TARGET="$2"; shift 2 ;;
    --latest-stable)  LATEST_STABLE=1; shift ;;
    --dry-run)        DRY_RUN=1; shift ;;
    -h|--help)        usage ;;
    *) echo "Unknown flag: $1" >&2; usage ;;
  esac
done

if [[ -z "$TARGET" && $LATEST_STABLE -eq 0 ]]; then
  echo "ERROR: --target <version> sau --latest-stable obligatoriu" >&2
  usage
fi

#─────────────────────────────────────────────────────────────────────────
# Helper: rezolvă versiune
#─────────────────────────────────────────────────────────────────────────
resolve_target() {
  if [[ $LATEST_STABLE -eq 1 ]]; then
    echo "[update-odoo] Querying Docker Hub for latest stable on 19.0..." >&2
    TARGET=$(curl -fsSL "https://hub.docker.com/v2/repositories/library/odoo/tags?name=19.0&page_size=100" \
      | jq -r '.results | map(.name) | map(select(test("^19\\.0-[0-9]+$"))) | sort | reverse | .[0]')
    if [[ -z "$TARGET" || "$TARGET" == "null" ]]; then
      echo "[update-odoo] ✗ Could not resolve latest stable" >&2
      exit 1
    fi
    echo "[update-odoo] Resolved latest stable: $TARGET" >&2
  fi
}

extract_digest() {
  local tag="$1"
  echo "[update-odoo] Pulling odoo:${tag}..." >&2
  docker pull "odoo:${tag}" >&2
  docker inspect "odoo:${tag}" \
    | jq -r '.[0].RepoDigests[]' \
    | grep -oE 'sha256:[a-f0-9]+' \
    | head -1
}

current_pin() {
  awk -F= '/^ARG ODOO_VERSION=/ {v=$2} /^ARG ODOO_DIGEST=/ {d=$2} END {print v"|"d}' "$DOCKERFILE"
}

#─────────────────────────────────────────────────────────────────────────
# Build staging container & smoke test
#─────────────────────────────────────────────────────────────────────────
build_staging() {
  local version="$1"
  local digest="$2"

  echo "[update-odoo] Building staging image..." >&2
  docker build \
    --build-arg "ODOO_VERSION=${version}" \
    --build-arg "ODOO_DIGEST=${digest}" \
    -t "$STAGING_TAG" \
    -f "$DOCKERFILE" \
    "${REPO_ROOT}"
}

#─────────────────────────────────────────────────────────────────────────
# Smoke test pentru staging container.
#
# Scope: validare BUILD + STARTUP + IMAGE INTEGRITY + RUNTIME DEPENDENCIES.
# Out of scope: tests funcționale care cer DB inițializată (login admin,
# install module, ANAF flow). Acelea se rulează în staging environment
# cu DB prepopulată, NU la fiecare update upstream.
#
# Failure mode: collect-all (rulează toate testele, raport agregat).
# Motivație: la upgrade-uri minore, vrem să vedem TOATE problemele odată,
# nu să iterăm pe fiecare în parte. Fail-fast doar pentru T1 critic
# (container running) — fără el, restul testelor n-au sens.
#─────────────────────────────────────────────────────────────────────────
run_smoke_test() {
  local version="$1"
  local failed_tests=()
  local passed_tests=()

  echo "[smoke-test] ─── Starting staging container ─────────────────" >&2
  docker rm -f "$STAGING_CONTAINER" 2>/dev/null || true

  # Container fără PostgreSQL real — smoke test verifică BINARUL + IMAGINEA,
  # nu integrarea cu DB. Override entrypoint cu sleep ca să putem face
  # docker exec fără ca Odoo să încerce conectarea la PG inexistent.
  if ! docker run -d --name "$STAGING_CONTAINER" \
       --entrypoint "" \
       "$STAGING_TAG" \
       sleep 300 2>&1; then
    echo "[smoke-test] ✗ T1 CRITICAL: Container failed to start. Aborting." >&2
    return 1
  fi
  passed_tests+=("T1: container running")
  trap "docker rm -f $STAGING_CONTAINER >/dev/null 2>&1 || true" EXIT

  echo "[smoke-test] ─── Test suite ─────────────────────────────────" >&2

  # T2: Image integrity — odoo binary present
  if docker exec "$STAGING_CONTAINER" bash -c \
       'test -x /usr/bin/odoo || test -x /usr/lib/python3/dist-packages/odoo/odoo-bin' \
       2>/dev/null; then
    passed_tests+=("T2: odoo binary present")
  else
    failed_tests+=("T2: odoo binary missing or non-executable")
  fi

  # T3: Python deps PAFF — uuid-utils + qrcode importabile
  if docker exec "$STAGING_CONTAINER" python3 -c \
       "import uuid_utils; import qrcode; print(uuid_utils.uuid7())" >/dev/null 2>&1; then
    passed_tests+=("T3: PAFF python deps importable (uuid-utils, qrcode)")
  else
    failed_tests+=("T3: PAFF python deps FAILED — Dockerfile RUN pip install broken")
  fi

  # T4: Odoo Python module loadable (config parser works)
  if docker exec "$STAGING_CONTAINER" python3 -c \
       "from odoo.tools import config; print('config OK')" >/dev/null 2>&1; then
    passed_tests+=("T4: Odoo Python module loadable")
  else
    failed_tests+=("T4: Odoo module FAILED — image corrupted or version mismatch")
  fi

  # T5: Patches/ folder structure (Layer 2 din ADR 0001)
  if docker exec "$STAGING_CONTAINER" test -d /opt/paff-patches; then
    passed_tests+=("T5: /opt/paff-patches present")
  else
    failed_tests+=("T5: /opt/paff-patches MISSING — Dockerfile COPY broken")
  fi

  # T6: Entrypoint script exists + executable
  if docker exec "$STAGING_CONTAINER" test -x /opt/paff-entrypoint.sh; then
    passed_tests+=("T6: entrypoint.sh executable")
  else
    failed_tests+=("T6: entrypoint.sh missing or not executable")
  fi

  # T7: Healthcheck script exists + executable
  if docker exec "$STAGING_CONTAINER" test -x /opt/paff-healthcheck.sh; then
    passed_tests+=("T7: healthcheck.sh executable")
  else
    failed_tests+=("T7: healthcheck.sh missing or not executable")
  fi

  # T8: Patches dry-run (dacă există patches/) — incompatibility detection
  local patches_count
  patches_count=$(ls -1 patches/*.patch 2>/dev/null | wc -l)
  if [[ "$patches_count" -gt 0 ]]; then
    if docker exec "$STAGING_CONTAINER" bash -c '
      cd /usr/lib/python3/dist-packages/odoo
      for p in /opt/paff-patches/*.patch; do
        patch -p1 --dry-run --silent < "$p" || exit 1
      done
    ' 2>/dev/null; then
      passed_tests+=("T8: $patches_count patches dry-run pass")
    else
      failed_tests+=("T8: patches dry-run FAILED — incompatibility cu noua versiune Odoo")
    fi
  else
    passed_tests+=("T8: skip (no patches to test)")
  fi

  # ─── Raport agregat ────────────────────────────────────────────────
  echo "[smoke-test] ─── Results ─────────────────────────────────────" >&2
  for t in "${passed_tests[@]}"; do
    echo "[smoke-test]   ✓ $t" >&2
  done
  for t in "${failed_tests[@]}"; do
    echo "[smoke-test]   ✗ $t" >&2
  done

  echo "[smoke-test] Summary: ${#passed_tests[@]} passed, ${#failed_tests[@]} failed" >&2

  if [[ "${#failed_tests[@]}" -gt 0 ]]; then
    echo "[smoke-test] ✗ Smoke test FAILED. Dockerfile NOT modified." >&2
    docker logs --tail=30 "$STAGING_CONTAINER" >&2 2>&1 || true
    return 1
  fi

  echo "[smoke-test] ✓ All smoke tests PASSED" >&2
  return 0
}

#─────────────────────────────────────────────────────────────────────────
# Main flow
#─────────────────────────────────────────────────────────────────────────
resolve_target
new_digest=$(extract_digest "$TARGET")
current=$(current_pin)
current_version="${current%%|*}"
current_digest="${current##*|}"

cat <<INFO
[update-odoo] ─── Update preview ────────────────────────────
  Current: odoo:${current_version}@${current_digest}
  Target:  odoo:${TARGET}@${new_digest}
INFO

if [[ "$current_digest" == "$new_digest" ]]; then
  echo "[update-odoo] Already on target digest. Nothing to do."
  exit 0
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo "[update-odoo] --dry-run: skipping build, smoke test, and Dockerfile update."
  exit 0
fi

build_staging "$TARGET" "$new_digest"
if ! run_smoke_test "$TARGET"; then
  echo "[update-odoo] ✗ Aborting: smoke test failed. Dockerfile NOT modified."
  exit 1
fi

#─────────────────────────────────────────────────────────────────────────
# Update Dockerfile + git stage
#─────────────────────────────────────────────────────────────────────────
read -rp "[update-odoo] Apply update to Dockerfile? [y/N] " confirm
if [[ "$confirm" != "y" ]]; then
  echo "[update-odoo] Aborted by user."
  exit 0
fi

sed -i.bak \
  -e "s|^ARG ODOO_VERSION=.*|ARG ODOO_VERSION=${TARGET}|" \
  -e "s|^ARG ODOO_DIGEST=.*|ARG ODOO_DIGEST=${new_digest}|" \
  "$DOCKERFILE"
rm -f "${DOCKERFILE}.bak"

echo "[update-odoo] ✓ Dockerfile updated."
echo "[update-odoo] Next steps:"
echo "  git diff docker/Dockerfile"
echo "  git add docker/Dockerfile"
echo "  git commit -m 'chore(odoo): bump runtime to ${TARGET}'"
