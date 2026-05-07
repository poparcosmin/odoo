#!/bin/bash
# backup-env.sh — backup criptat al fișierelor sensibile (.env, secrets).
#
# Folosește age cu public key (asymmetric encryption). Restore necesită
# private key salvată OFFLINE la ~/.age/paff-backup.key — printate pe hârtie
# în safe sau Bitwarden secure note.
#
# CRITICAL: dacă pierzi private key-ul, backup-urile encrypted devin
# IRECUPERABILE. Salvează cheia în 2 locuri (safe fizic + cloud password manager).
#
# Usage:
#   scripts/backup-env.sh
#   scripts/backup-env.sh --restore <backup-file.age> [target_dir]
#
# Restore:
#   age -d -i ~/.age/paff-backup.key data/backup/env/env-20260507-...age \
#     | tar xzf - -C /tmp/restored-env

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${REPO_ROOT}/data/backup/env"
AGE_KEY="${HOME}/.age/paff-backup.key"
RETENTION_DAILY=30
RETENTION_MONTHLY=12

# Public key extracted din keyfile (poate fi referenced via -R flag)
if [[ ! -f "$AGE_KEY" ]]; then
  echo "ERROR: age key missing at $AGE_KEY" >&2
  echo "Generate cu: age-keygen -o $AGE_KEY" >&2
  exit 1
fi

PUB_KEY=$(grep "^# public key:" "$AGE_KEY" | cut -d' ' -f4)
if [[ -z "$PUB_KEY" ]]; then
  echo "ERROR: no public key found in $AGE_KEY" >&2
  exit 1
fi

# ─── RESTORE MODE ──────────────────────────────────────────────────────
if [[ "${1:-}" == "--restore" ]]; then
  BACKUP_FILE="${2:-}"
  TARGET_DIR="${3:-/tmp/restored-env}"
  if [[ -z "$BACKUP_FILE" || ! -f "$BACKUP_FILE" ]]; then
    echo "Usage: $0 --restore <backup-file.age> [target_dir=/tmp/restored-env]" >&2
    exit 1
  fi
  mkdir -p "$TARGET_DIR"
  echo "[restore-env] Decrypting $BACKUP_FILE → $TARGET_DIR ..."
  age -d -i "$AGE_KEY" "$BACKUP_FILE" | tar xzf - -C "$TARGET_DIR"
  echo "[restore-env] ✓ Restored to $TARGET_DIR"
  exit 0
fi

# ─── BACKUP MODE ───────────────────────────────────────────────────────
mkdir -p "$BACKUP_DIR"

TS=$(date +%Y%m%d-%H%M%S)
DOM=$(date +%d)
# Determine retention type: 1st of month → save în monthly subfolder
if [[ "$DOM" == "01" ]]; then
  SUBDIR="monthly"
  RETENTION=$RETENTION_MONTHLY
else
  SUBDIR="daily"
  RETENTION=$RETENTION_DAILY
fi
DEST="${BACKUP_DIR}/${SUBDIR}"
mkdir -p "$DEST"

OUT="${DEST}/env-${TS}.tar.gz.age"

echo "[backup-env] Encrypting sensitive files → $OUT"

# Files to backup (sensitive — NU în git)
SENSITIVE_FILES=(
  ".env"
)

# Verify all sensitive files exist
MISSING=()
for f in "${SENSITIVE_FILES[@]}"; do
  if [[ ! -f "${REPO_ROOT}/${f}" ]]; then
    MISSING+=("$f")
  fi
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "[backup-env] WARNING: missing files: ${MISSING[*]}" >&2
fi

# Tar + encrypt în pipe (NU scriem fișier intermediar plaintext)
cd "$REPO_ROOT"
tar czf - "${SENSITIVE_FILES[@]}" 2>/dev/null \
  | age -r "$PUB_KEY" \
  > "$OUT"

SIZE=$(du -h "$OUT" | cut -f1)
echo "[backup-env]   Encrypted: $SIZE"

# Apply retention
echo "[backup-env] Applying retention ($SUBDIR → keep last $RETENTION)..."
ls -1tr "$DEST"/env-*.tar.gz.age 2>/dev/null \
  | head -n "-${RETENTION}" \
  | while read -r old; do
      echo "[backup-env]   Pruning: $(basename "$old")"
      rm -f "$old"
    done

echo "[backup-env] ✓ Done: $OUT"
echo "[backup-env]   To restore: $0 --restore $OUT"
