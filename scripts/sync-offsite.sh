#!/bin/bash
# sync-offsite.sh — copy backup-uri locale la Google Drive (offsite 3-2-1).
#
# Folosește rclone cu remote 'drive:' (Google Drive) deja configurat.
# Sync incremental (NU re-upload tot, doar diff).
#
# Usage:
#   scripts/sync-offsite.sh
#   scripts/sync-offsite.sh --remote drive:custom-folder
#
# Pe Google Drive, folder structure:
#   paff-odoo-backup/
#     ├── daily/
#     ├── weekly/
#     ├── monthly/
#     ├── env/
#     └── manual/

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_BACKUP="${REPO_ROOT}/data/backup"
REMOTE_DEFAULT="drive:paff-odoo-backup"

REMOTE="${REMOTE_DEFAULT}"
if [[ "${1:-}" == "--remote" ]]; then
  REMOTE="$2"
fi

echo "[sync-offsite] Source: $LOCAL_BACKUP"
echo "[sync-offsite] Target: $REMOTE"

# Verify rclone configured
if ! rclone listremotes 2>/dev/null | grep -q "^${REMOTE%%:*}:$"; then
  echo "FAIL: rclone remote '${REMOTE%%:*}' not configured" >&2
  echo "       Run: rclone config" >&2
  exit 1
fi

# Verify local backup dir exists + has content
if [[ ! -d "$LOCAL_BACKUP" ]]; then
  echo "FAIL: local backup dir missing: $LOCAL_BACKUP" >&2
  exit 1
fi

LOCAL_SIZE=$(du -sh "$LOCAL_BACKUP" 2>/dev/null | cut -f1)
echo "[sync-offsite] Local size: $LOCAL_SIZE"

# Sync incremental (rclone copy preservă timestamps + checksums)
# --transfers=4 (concurrent uploads), --checkers=8 (concurrent metadata)
# --update doar dacă remote e mai vechi
# --skip-links evită loops symlinks
echo "[sync-offsite] rclone copy (incremental)..."
rclone copy "$LOCAL_BACKUP" "$REMOTE" \
  --transfers=4 \
  --checkers=8 \
  --update \
  --skip-links \
  --stats=10s \
  --stats-one-line \
  --log-level INFO 2>&1 \
  | tail -20

# Verify remote integrity (size match)
REMOTE_SIZE=$(rclone size "$REMOTE" --json 2>/dev/null | python3 -c 'import sys, json; d = json.load(sys.stdin); print(d.get("bytes", 0))')
LOCAL_BYTES=$(du -sb "$LOCAL_BACKUP" 2>/dev/null | cut -f1)

echo "[sync-offsite] Local: ${LOCAL_BYTES} bytes"
echo "[sync-offsite] Remote: ${REMOTE_SIZE} bytes"

# Allow some discrepancy (Google Drive metadata overhead ~1%)
if [[ "$REMOTE_SIZE" -ge "$((LOCAL_BYTES * 99 / 100))" ]]; then
  echo "[sync-offsite] ✓ Sync verified (sizes match within tolerance)"
  exit 0
else
  echo "[sync-offsite] ✗ Size mismatch (remote=$REMOTE_SIZE, local=$LOCAL_BYTES)" >&2
  exit 1
fi
