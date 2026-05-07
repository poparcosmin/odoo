#!/bin/bash
# notify.sh — send notification via Telegram + Gmail SMTP.
#
# Required env vars (load din .env or pass explicit):
#   PAFF_TG_BOT_TOKEN     — Telegram bot token from @BotFather
#   PAFF_TG_CHAT_ID       — Telegram chat ID where bot posts (your DM or group)
#   GMAIL_APP_PASSWORD    — Gmail App Password (16-char, NOT regular password)
#                           Generate at: myaccount.google.com/apppasswords
#   PAFF_NOTIFY_EMAIL     — recipient email (default: paff.office@gmail.com)
#   PAFF_SMTP_USER        — Gmail sender (default: paff.office@gmail.com)
#
# Usage:
#   scripts/notify.sh "Subject" "Body text"
#   scripts/notify.sh --severity error "Backup FAIL" "Details..."
#
# Exit codes: 0 OK, 1 transport error (network, auth)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load .env dacă există (pentru env vars)
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a; source "${REPO_ROOT}/.env"; set +a
fi

# Parse args
SEVERITY="info"
if [[ "${1:-}" == "--severity" ]]; then
  SEVERITY="$2"
  shift 2
fi

SUBJECT="${1:-PAFF Notification}"
BODY="${2:-(no body)}"

# Severity emoji
case "$SEVERITY" in
  error)   ICON="🔴" ;;
  warn)    ICON="🟡" ;;
  ok)      ICON="🟢" ;;
  info|*)  ICON="ℹ️" ;;
esac

HOST=$(hostname)
TS=$(date '+%Y-%m-%d %H:%M:%S %Z')

FULL_MSG="$ICON [PAFF] $SUBJECT
$BODY

Host: $HOST
Time: $TS"

# ─── Telegram ──────────────────────────────────────────────────────────
if [[ -n "${PAFF_TG_BOT_TOKEN:-}" && -n "${PAFF_TG_CHAT_ID:-}" ]]; then
  TG_RESP=$(curl -s -X POST \
    "https://api.telegram.org/bot${PAFF_TG_BOT_TOKEN}/sendMessage" \
    -d chat_id="${PAFF_TG_CHAT_ID}" \
    -d text="$FULL_MSG" \
    -d parse_mode=Markdown 2>&1)
  if echo "$TG_RESP" | grep -q '"ok":true'; then
    echo "[notify] ✓ Telegram delivered"
  else
    echo "[notify] ✗ Telegram failed: $TG_RESP" >&2
  fi
else
  echo "[notify] ⚠ Telegram skipped (PAFF_TG_BOT_TOKEN/PAFF_TG_CHAT_ID not set)"
fi

# ─── Email via Python smtplib ──────────────────────────────────────────
# Defaults pentru sender + recipient (override doar dacă user vrea altceva)
SMTP_USER="${PAFF_SMTP_USER:-paff.office@gmail.com}"
NOTIFY_EMAIL="${PAFF_NOTIFY_EMAIL:-paff.office@gmail.com}"
SMTP_PASS="${GMAIL_APP_PASSWORD:-}"

if [[ -n "$SMTP_PASS" ]]; then
  python3 - <<PYEOF 2>&1 || echo "[notify] ✗ Email failed" >&2
import smtplib, ssl
from email.message import EmailMessage
import sys

msg = EmailMessage()
msg['From']    = '${SMTP_USER}'
msg['To']      = '${NOTIFY_EMAIL}'
msg['Subject'] = '${ICON} [PAFF] ${SUBJECT}'
msg.set_content(r"""${BODY}

Host: ${HOST}
Time: ${TS}
Severity: ${SEVERITY}
""")

ctx = ssl.create_default_context()
try:
    with smtplib.SMTP_SSL('smtp.gmail.com', 465, context=ctx) as s:
        s.login('${SMTP_USER}', '${SMTP_PASS}')
        s.send_message(msg)
    print('[notify] ✓ Email delivered to ${NOTIFY_EMAIL}')
except Exception as e:
    print(f'[notify] ✗ Email failed: {e}', file=sys.stderr)
    sys.exit(1)
PYEOF
else
  echo "[notify] ⚠ Email skipped (GMAIL_APP_PASSWORD not set in .env)"
fi
