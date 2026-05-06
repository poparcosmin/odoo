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
#   scripts/update-odoo.sh --target 19.0.20260601
#   scripts/update-odoo.sh --latest-stable
#   scripts/update-odoo.sh --dry-run --target 19.0.20260601

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
    TARGET=$(curl -fsSL "https://hub.docker.com/v2/repositories/library/odoo/tags?name=19.0.&page_size=20" \
      | jq -r '.results | map(.name) | map(select(test("^19\\.0\\.[0-9]+$"))) | sort | reverse | .[0]')
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

run_smoke_test() {
  local version="$1"

  echo "[update-odoo] Starting staging container..." >&2
  docker rm -f "$STAGING_CONTAINER" 2>/dev/null || true
  docker run -d --name "$STAGING_CONTAINER" \
    --network paff_apps 2>/dev/null \
    "$STAGING_TAG" || \
  docker run -d --name "$STAGING_CONTAINER" "$STAGING_TAG"

  trap "docker rm -f $STAGING_CONTAINER >/dev/null 2>&1 || true" EXIT

  #─────────────────────────────────────────────────────────────────────
  # TODO USER: definește smoke test conditions concrete pentru PAFF.
  #
  # Întrebări de răspuns (5-10 linii bash mai jos):
  #   1. Cât timp e acceptabil pentru container să devină healthy?
  #      (default propus: 60s — modifică dacă PAFF Odoo are startup mai lung)
  #   2. /web/health 200 e suficient sau vrei și un test funcțional?
  #      Exemple test funcțional:
  #        - Login admin → response 200 (verifică auth flow)
  #        - GET /web/dataset/call_kw cu res.partner.search → JSON valid
  #        - Creare partner test cu CIF "RO12345678" → ANAF lookup OK
  #   3. Ce condiții fiscale RO trebuie să meargă? (l10n_ro_* loaded?)
  #
  # Recomandare: începe simplu (health endpoint + un assert critic),
  # adaugă condiții pe măsură ce descoperi failure modes.
  #─────────────────────────────────────────────────────────────────────

  local timeout=60   # TODO USER: ajustează threshold
  local elapsed=0
  echo "[update-odoo] Waiting for healthcheck (timeout: ${timeout}s)..." >&2
  while [[ $elapsed -lt $timeout ]]; do
    health=$(docker inspect --format='{{.State.Health.Status}}' "$STAGING_CONTAINER" 2>/dev/null || echo "unknown")
    if [[ "$health" == "healthy" ]]; then
      echo "[update-odoo] ✓ Container healthy at ${elapsed}s" >&2
      break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  if [[ "$health" != "healthy" ]]; then
    echo "[update-odoo] ✗ Container unhealthy after ${timeout}s" >&2
    docker logs --tail=50 "$STAGING_CONTAINER" >&2
    return 1
  fi

  # TODO USER: adaugă aici asserții suplimentare. Exemple:
  #
  # # Test 1: /web/health endpoint OK
  # docker exec "$STAGING_CONTAINER" curl -sf http://localhost:8069/web/health || return 1
  #
  # # Test 2: Login admin reușit (necesită DB initializată)
  # # docker exec "$STAGING_CONTAINER" odoo shell -d test_db --no-http <<< \
  # #   'env["res.users"].browse(1).login' || return 1
  #
  # # Test 3: Module l10n_ro instalabil (dependențe corecte)
  # # docker exec "$STAGING_CONTAINER" \
  # #   odoo --test-enable --stop-after-init -d test_db -i l10n_ro || return 1

  echo "[update-odoo] ✓ Smoke test PASSED" >&2
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
