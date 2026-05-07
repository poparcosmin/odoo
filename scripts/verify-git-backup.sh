#!/bin/bash
# verify-git-backup.sh — verifică code backup status (git remote + submodule).
#
# Code backup = git push to origin (GitHub). Acest script verifică:
# - No uncommitted changes pe branch active
# - All branches synced cu upstream (no orphan commits)
# - Submodule l10n-romania up-to-date
#
# Usage: scripts/verify-git-backup.sh [--strict]
#   --strict  =  fail on warnings (use în CI)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

STRICT=0
[[ "${1:-}" == "--strict" ]] && STRICT=1

WARNINGS=0
ERRORS=0

echo "════════════════════════════════════════════════════════════════"
echo "  VERIFY GIT BACKUP — $REPO_ROOT"
echo "════════════════════════════════════════════════════════════════"

# ─── 1. Uncommitted changes (excluding allowed) ────────────────────────
# Allowed unommitted: .env, .env.bak.*, data/, src/odoo/, logs/
UNCOMMITTED=$(git status --porcelain | grep -vE '\.env|\.env\.bak|^.. data/|^.. src/odoo/|^.. logs/|^.. src/assets/' || true)
if [[ -n "$UNCOMMITTED" ]]; then
  echo "[1] ⚠ Uncommitted changes (excluding ignored):"
  echo "$UNCOMMITTED" | sed 's/^/    /'
  WARNINGS=$((WARNINGS + 1))
else
  echo "[1] ✓ No uncommitted changes (excluding .env, data/, src/odoo/)"
fi

# ─── 2. Current branch upstream tracking ───────────────────────────────
CURRENT_BRANCH=$(git branch --show-current)
UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name "@{upstream}" 2>/dev/null || echo "")
if [[ -z "$UPSTREAM" ]]; then
  echo "[2] ✗ Branch '$CURRENT_BRANCH' has NO upstream tracking"
  ERRORS=$((ERRORS + 1))
else
  echo "[2] ✓ Branch '$CURRENT_BRANCH' tracks '$UPSTREAM'"
fi

# ─── 3. Orphan commits (local commits NOT pushed) ──────────────────────
if [[ -n "$UPSTREAM" ]]; then
  AHEAD=$(git rev-list --count "${UPSTREAM}..HEAD" 2>/dev/null || echo "0")
  if [[ "$AHEAD" -gt 0 ]]; then
    echo "[3] ⚠ $AHEAD local commit(s) NOT pushed to $UPSTREAM:"
    git log --oneline "${UPSTREAM}..HEAD" 2>&1 | sed 's/^/    /'
    WARNINGS=$((WARNINGS + 1))
  else
    echo "[3] ✓ All local commits pushed to $UPSTREAM"
  fi
fi

# ─── 4. Other branches with unpushed commits ───────────────────────────
ORPHAN_BRANCHES=$(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads/ \
  | grep -E 'ahead' | awk '{print $1}' | grep -v "^${CURRENT_BRANCH}$" || true)
if [[ -n "$ORPHAN_BRANCHES" ]]; then
  echo "[4] ⚠ Other branches with unpushed commits:"
  echo "$ORPHAN_BRANCHES" | sed 's/^/    /'
  WARNINGS=$((WARNINGS + 1))
else
  echo "[4] ✓ No other branches with unpushed commits"
fi

# ─── 5. Submodule status ───────────────────────────────────────────────
SUBMODULE_STATUS=$(git submodule status 2>/dev/null || echo "")
if [[ -n "$SUBMODULE_STATUS" ]]; then
  # Check pentru "+", "-", "U" prefix (modified, uninitialized, conflict)
  PROBLEM_SM=$(echo "$SUBMODULE_STATUS" | grep -E '^[+\-U]' || true)
  if [[ -n "$PROBLEM_SM" ]]; then
    echo "[5] ⚠ Submodule issues:"
    echo "$PROBLEM_SM" | sed 's/^/    /'
    WARNINGS=$((WARNINGS + 1))
  else
    SM_COUNT=$(echo "$SUBMODULE_STATUS" | wc -l)
    echo "[5] ✓ All submodules ($SM_COUNT) in clean state"
  fi
fi

# ─── 6. Remote reachability ────────────────────────────────────────────
REMOTES=$(git remote 2>&1)
for remote in $REMOTES; do
  if git ls-remote --exit-code "$remote" >/dev/null 2>&1; then
    REMOTE_URL=$(git remote get-url "$remote")
    echo "[6] ✓ Remote '$remote' reachable: $REMOTE_URL"
  else
    echo "[6] ✗ Remote '$remote' NOT reachable (network or auth issue)"
    ERRORS=$((ERRORS + 1))
  fi
done

# ─── Final report ──────────────────────────────────────────────────────
echo
if [[ "$ERRORS" -gt 0 ]]; then
  echo "❌ FAILED — $ERRORS error(s), $WARNINGS warning(s)"
  exit 1
elif [[ "$WARNINGS" -gt 0 ]]; then
  if [[ "$STRICT" -eq 1 ]]; then
    echo "❌ FAILED (strict mode) — $WARNINGS warning(s)"
    exit 1
  fi
  echo "⚠ PASSED with $WARNINGS warning(s)"
  exit 0
else
  echo "✅ PASSED — all checks clean"
  exit 0
fi
