#!/bin/bash
# health-monitor.sh — observability minim PAFF Odoo (M3 Phase 1).
#
# Daily run la 09:00 (cron). Checks:
#   1. Disk usage > 80% → alert
#   2. RAM usage Odoo container (%)
#   3. PG connections active vs max
#   4. Backup freshness (last daily < 26h)
#   5. Cron health (failed_count > 0 or auto-deactivated)
#   6. SSL certificate expiry (dacă există VPS deploy)
#   7. /web/health HTTP probe (must return 200)
#   8. Disk free în filestore volume
#
# Severity logic:
#   - error: critical issues (HTTP down, backup stale > 48h, disk > 90%)
#   - warn:  caution issues (disk > 80%, RAM > 75%, cron failures)
#   - ok:    all clean (don't notify, just log)
#
# Notifications via scripts/notify.sh (Telegram + email).
#
# Usage:
#   scripts/health-monitor.sh           # full check, notify only on issues
#   scripts/health-monitor.sh --verbose # log all checks (no notify)
#   scripts/health-monitor.sh --notify-ok # notify even when OK (weekly summary)

set -uo pipefail  # NU -e (vrem rulare completă)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${REPO_ROOT}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/health-$(date +%Y%m%d).log"

VERBOSE=0
NOTIFY_OK=0
[[ "${1:-}" == "--verbose" ]] && VERBOSE=1
[[ "${1:-}" == "--notify-ok" ]] && NOTIFY_OK=1

PG_USER="${PG_USER:-odoo_user}"
DB_NAME="${DB_NAME:-paff_prod}"

ERRORS=()
WARNS=()
OK_COUNT=0

log() {
  echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

verbose() {
  [[ "$VERBOSE" -eq 1 ]] && log "    $*"
}

# ═══════════════════════════════════════════════════════════════════════
# CHECK 1 — Disk usage host
# ═══════════════════════════════════════════════════════════════════════
DISK_USE=$(df / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
if [[ -z "$DISK_USE" ]]; then
  WARNS+=("disk: cannot read /")
elif [[ "$DISK_USE" -ge 90 ]]; then
  ERRORS+=("disk usage CRITICAL: ${DISK_USE}%")
elif [[ "$DISK_USE" -ge 80 ]]; then
  WARNS+=("disk usage HIGH: ${DISK_USE}%")
else
  OK_COUNT=$((OK_COUNT + 1))
  verbose "disk: ${DISK_USE}% (OK)"
fi

# ═══════════════════════════════════════════════════════════════════════
# CHECK 2 — RAM Odoo container
# ═══════════════════════════════════════════════════════════════════════
RAM_PCT=$(docker stats paff-erp-odoo --no-stream --format '{{.MemPerc}}' 2>/dev/null | tr -d '%')
if [[ -z "$RAM_PCT" ]]; then
  ERRORS+=("RAM: cannot read paff-erp-odoo stats (container down?)")
else
  RAM_INT=$(printf '%.0f' "$RAM_PCT" 2>/dev/null || echo "0")
  if [[ "$RAM_INT" -ge 90 ]]; then
    ERRORS+=("RAM Odoo CRITICAL: ${RAM_PCT}%")
  elif [[ "$RAM_INT" -ge 75 ]]; then
    WARNS+=("RAM Odoo HIGH: ${RAM_PCT}%")
  else
    OK_COUNT=$((OK_COUNT + 1))
    verbose "RAM Odoo: ${RAM_PCT}% (OK)"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════
# CHECK 3 — PG connections
# ═══════════════════════════════════════════════════════════════════════
PG_ACTIVE=$(docker exec paff-erp-postgres psql -U "$PG_USER" -d postgres -tAc \
  "SELECT count(*) FROM pg_stat_activity WHERE state='active'" 2>/dev/null)
PG_MAX=$(docker exec paff-erp-postgres psql -U "$PG_USER" -d postgres -tAc \
  "SHOW max_connections" 2>/dev/null)

if [[ -n "$PG_ACTIVE" && -n "$PG_MAX" ]]; then
  PG_PCT=$((PG_ACTIVE * 100 / PG_MAX))
  if [[ "$PG_PCT" -ge 80 ]]; then
    WARNS+=("PG connections: ${PG_ACTIVE}/${PG_MAX} (${PG_PCT}%)")
  else
    OK_COUNT=$((OK_COUNT + 1))
    verbose "PG: ${PG_ACTIVE}/${PG_MAX} (${PG_PCT}%)"
  fi
else
  WARNS+=("PG: cannot read connection stats")
fi

# ═══════════════════════════════════════════════════════════════════════
# CHECK 4 — Backup freshness
# ═══════════════════════════════════════════════════════════════════════
LATEST_BACKUP=$(ls -1dt "${REPO_ROOT}/data/backup/daily/${DB_NAME}-"* 2>/dev/null | head -1)
if [[ -z "$LATEST_BACKUP" ]]; then
  ERRORS+=("backup: NO daily backup found")
else
  BACKUP_AGE_S=$(($(date +%s) - $(stat -c %Y "$LATEST_BACKUP")))
  BACKUP_AGE_H=$((BACKUP_AGE_S / 3600))
  if [[ "$BACKUP_AGE_H" -ge 48 ]]; then
    ERRORS+=("backup STALE: latest is ${BACKUP_AGE_H}h old")
  elif [[ "$BACKUP_AGE_H" -ge 26 ]]; then
    WARNS+=("backup outdated: ${BACKUP_AGE_H}h old (cron run?)")
  else
    OK_COUNT=$((OK_COUNT + 1))
    verbose "backup: ${BACKUP_AGE_H}h old (OK)"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════
# CHECK 5 — Cron health (B6 inclus aici)
# ═══════════════════════════════════════════════════════════════════════
FAILED_CRONS=$(docker exec paff-erp-postgres psql -U "$PG_USER" -d "$DB_NAME" -tAc "
  SELECT count(*) FROM ir_cron
  WHERE failure_count > 0 OR (active = false AND failure_count >= 5)
" 2>/dev/null)

DEACTIVATED_CRONS=$(docker exec paff-erp-postgres psql -U "$PG_USER" -d "$DB_NAME" -tAc "
  SELECT count(*) FROM ir_cron WHERE active = false AND failure_count >= 5
" 2>/dev/null)

if [[ "${FAILED_CRONS:-0}" -gt 0 ]]; then
  if [[ "${DEACTIVATED_CRONS:-0}" -gt 0 ]]; then
    ERRORS+=("crons: ${FAILED_CRONS} cu failures, ${DEACTIVATED_CRONS} auto-deactivated")
  else
    WARNS+=("crons: ${FAILED_CRONS} cu failures")
  fi
else
  OK_COUNT=$((OK_COUNT + 1))
  verbose "crons: 0 failures"
fi

# ═══════════════════════════════════════════════════════════════════════
# CHECK 6 — SSL cert expiry (DOAR dacă există VPS deploy = erp.paff.ro)
# ═══════════════════════════════════════════════════════════════════════
if command -v openssl >/dev/null 2>&1; then
  CERT_FILE="/etc/letsencrypt/live/erp.paff.ro/cert.pem"
  if [[ -f "$CERT_FILE" ]]; then
    EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT_FILE" 2>/dev/null | cut -d= -f2)
    EXPIRY_S=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null)
    NOW_S=$(date +%s)
    DAYS_LEFT=$(( (EXPIRY_S - NOW_S) / 86400 ))
    if [[ "$DAYS_LEFT" -lt 7 ]]; then
      ERRORS+=("SSL cert: ${DAYS_LEFT} days left")
    elif [[ "$DAYS_LEFT" -lt 14 ]]; then
      WARNS+=("SSL cert: ${DAYS_LEFT} days left")
    else
      OK_COUNT=$((OK_COUNT + 1))
      verbose "SSL cert: ${DAYS_LEFT} days left"
    fi
  else
    verbose "SSL cert: not deployed yet (Phase 3)"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════
# CHECK 7 — HTTP probe /web/health
# ═══════════════════════════════════════════════════════════════════════
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8310/web/health 2>/dev/null)
if [[ "$HTTP_CODE" == "200" ]]; then
  OK_COUNT=$((OK_COUNT + 1))
  verbose "HTTP /web/health: 200 OK"
else
  ERRORS+=("HTTP /web/health: ${HTTP_CODE:-000} (not 200)")
fi

# ═══════════════════════════════════════════════════════════════════════
# CHECK 8 — Filestore disk usage
# ═══════════════════════════════════════════════════════════════════════
FS_SIZE=$(docker exec paff-erp-odoo \
  du -sb "/var/lib/odoo/filestore/${DB_NAME}" 2>/dev/null | cut -f1)
if [[ -n "$FS_SIZE" ]]; then
  FS_MB=$((FS_SIZE / 1024 / 1024))
  OK_COUNT=$((OK_COUNT + 1))
  verbose "filestore: ${FS_MB}MB"
else
  WARNS+=("filestore: cannot read size")
fi

# ═══════════════════════════════════════════════════════════════════════
# REPORT + NOTIFY
# ═══════════════════════════════════════════════════════════════════════
log "─────────────────────────────────────────────────────────"
TOTAL_CHECKS=$((${#ERRORS[@]} + ${#WARNS[@]} + OK_COUNT))
log "Health check: $OK_COUNT/$TOTAL_CHECKS OK | ${#WARNS[@]} warns | ${#ERRORS[@]} errors"

# Determine severity for notify
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  SEVERITY="error"
  SUBJECT="Health CRITICAL"
  BODY="ERRORS:
$(printf '  - %s\n' "${ERRORS[@]}")

WARNINGS:
$(printf '  - %s\n' "${WARNS[@]}")

OK: $OK_COUNT/$TOTAL_CHECKS"
elif [[ ${#WARNS[@]} -gt 0 ]]; then
  SEVERITY="warn"
  SUBJECT="Health warnings"
  BODY="WARNINGS:
$(printf '  - %s\n' "${WARNS[@]}")

OK: $OK_COUNT/$TOTAL_CHECKS"
else
  SEVERITY="ok"
  SUBJECT="Health OK"
  BODY="All $TOTAL_CHECKS checks passed clean."
fi

# Notify policy:
# - error/warn: ALWAYS notify
# - ok: notify ONLY dacă --notify-ok flag (weekly summary mode)
if [[ "$SEVERITY" == "error" || "$SEVERITY" == "warn" ]]; then
  "$REPO_ROOT/scripts/notify.sh" --severity "$SEVERITY" "$SUBJECT" "$BODY" \
    >> "$LOG_FILE" 2>&1 || log "WARNING: notify.sh failed"
elif [[ "$NOTIFY_OK" -eq 1 ]]; then
  "$REPO_ROOT/scripts/notify.sh" --severity ok "$SUBJECT" "$BODY" \
    >> "$LOG_FILE" 2>&1 || log "WARNING: notify.sh failed"
fi

# Exit code
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  exit 2
elif [[ ${#WARNS[@]} -gt 0 ]]; then
  exit 1
else
  exit 0
fi
