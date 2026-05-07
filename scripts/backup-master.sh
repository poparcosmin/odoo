#!/bin/bash
# backup-master.sh — orchestrator unificat pentru tot pipeline-ul backup PAFF.
#
# Pipeline (per zi):
#   1. backup-db.sh (auto-detect type: monthly DOM=01, weekly Sunday, else daily)
#   2. backup-env.sh (encrypted .env via age)
#   3. verify-git-backup.sh (code in git push status)
#   4. verify-backup.sh (LAST DAILY restore test) — monthly only (D5 user choice)
#   5. sync-offsite.sh (Google Drive) — weekly post-backup (Sunday)
#   6. notify.sh (Telegram + email — final status)
#
# Cron strategy: rulez asta zilnic la 03:00 RO. Script-ul detectează
# context (DOW, DOM) și aplică sub-task-urile corespunzătoare.
#
# Usage:
#   scripts/backup-master.sh            # auto-mode (detect type)
#   scripts/backup-master.sh --dry-run  # show what would run
#
# Logs: ~/Work/Odoo/logs/backup-YYYYMMDD.log

set -uo pipefail  # NU -e — vrem să rulăm tot, raportăm la final

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${REPO_ROOT}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/backup-$(date +%Y%m%d).log"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# Determine context
DOW=$(date +%u)        # 1-7 (Monday=1, Sunday=7)
DOM=$(date +%d)        # 01-31
DATE_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')
TODAY=$(date +%Y%m%d)

if [[ "$DOM" == "01" ]]; then
  BACKUP_TYPE="monthly"
elif [[ "$DOW" == "7" ]]; then
  BACKUP_TYPE="weekly"
else
  BACKUP_TYPE="daily"
fi

# Per D5 user choice: verify-backup MONTHLY only
RUN_VERIFY_BACKUP=0
[[ "$DOM" == "01" ]] && RUN_VERIFY_BACKUP=1

# Sync offsite WEEKLY (Sunday) sau MONTHLY (1st)
RUN_SYNC_OFFSITE=0
[[ "$DOW" == "7" || "$DOM" == "01" ]] && RUN_SYNC_OFFSITE=1

# ─── Logging helpers ───────────────────────────────────────────────────
log() {
  local msg="[$(date '+%H:%M:%S')] $*"
  echo "$msg" | tee -a "$LOG_FILE"
}

run_step() {
  local name="$1"
  shift
  local cmd="$*"
  log "▶ $name: $cmd"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "  (dry-run, skipped)"
    return 0
  fi
  if eval "$cmd" >> "$LOG_FILE" 2>&1; then
    log "  ✓ $name OK"
    return 0
  else
    local exit_code=$?
    log "  ✗ $name FAILED (exit $exit_code)"
    return $exit_code
  fi
}

# ─── Track failures ────────────────────────────────────────────────────
FAILED_STEPS=()

# ─── Header ────────────────────────────────────────────────────────────
DRY_BANNER=""
[[ "$DRY_RUN" -eq 1 ]] && DRY_BANNER=" (DRY-RUN)"
log "════════════════════════════════════════════════════════════════"
log "  BACKUP MASTER — $DATE_HUMAN — type=$BACKUP_TYPE$DRY_BANNER"
log "  DOW=$DOW DOM=$DOM | verify=$RUN_VERIFY_BACKUP | offsite=$RUN_SYNC_OFFSITE"
log "════════════════════════════════════════════════════════════════"

cd "$REPO_ROOT"

# ─── Step 1: DB + filestore backup ─────────────────────────────────────
if ! run_step "DB-backup" "$REPO_ROOT/scripts/backup-db.sh paff_prod $BACKUP_TYPE"; then
  FAILED_STEPS+=("DB-backup")
fi

# ─── Step 2: env backup ────────────────────────────────────────────────
if ! run_step "env-backup" "$REPO_ROOT/scripts/backup-env.sh"; then
  FAILED_STEPS+=("env-backup")
fi

# ─── Step 3: git verify (no orphan commits) ────────────────────────────
if ! run_step "git-verify" "$REPO_ROOT/scripts/verify-git-backup.sh"; then
  # Git warnings are not critical (uncommitted changes during work)
  log "  (git warnings tolerated)"
fi

# ─── Step 4: verify-backup (monthly per D5) ────────────────────────────
if [[ "$RUN_VERIFY_BACKUP" -eq 1 ]]; then
  if ! run_step "verify-backup" "$REPO_ROOT/scripts/verify-backup.sh"; then
    FAILED_STEPS+=("verify-backup")
  fi
fi

# ─── Step 5: offsite sync (weekly + monthly) ───────────────────────────
if [[ "$RUN_SYNC_OFFSITE" -eq 1 ]]; then
  if ! run_step "sync-offsite" "$REPO_ROOT/scripts/sync-offsite.sh"; then
    FAILED_STEPS+=("sync-offsite")
  fi
fi

# ─── Final summary + notification ──────────────────────────────────────
log "─────────────────────────────────────────────────────────────────"
if [[ ${#FAILED_STEPS[@]} -eq 0 ]]; then
  log "✅ ALL STEPS PASSED"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    "$REPO_ROOT/scripts/notify.sh" --severity ok \
      "Backup $BACKUP_TYPE OK" \
      "All steps passed. Log: $LOG_FILE" \
      >> "$LOG_FILE" 2>&1 || true
  fi
  exit 0
else
  log "❌ FAILED STEPS: ${FAILED_STEPS[*]}"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    "$REPO_ROOT/scripts/notify.sh" --severity error \
      "Backup $BACKUP_TYPE FAILED" \
      "Failed steps: ${FAILED_STEPS[*]}. Log: $LOG_FILE" \
      >> "$LOG_FILE" 2>&1 || true
  fi
  exit 1
fi
