#!/bin/bash
# check-odoo-update.sh — verifică zilnic Docker Hub pentru update-uri Odoo.
#
# Rulat de cron-monitor PAFF zilnic la 07:00.
# Output: stdout cu severity classification, exit code distinct per nivel.
#
# Exit codes:
#   0  — no update available
#   10 — patch update (low severity)
#   20 — minor update (normal severity)
#   30 — security CVE detected (urgent)
#   1  — script error (network, parse, etc.)
#
# Folosit de cron monitor → Telegram bot (skill `tg`) → GitHub issue auto-create

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="${REPO_ROOT}/docker/Dockerfile"

current_version=$(awk -F= '/^ARG ODOO_VERSION=/ {print $2}' "$DOCKERFILE")
if [[ -z "$current_version" ]]; then
  echo "ERROR: cannot parse ARG ODOO_VERSION from $DOCKERFILE" >&2
  exit 1
fi

#─────────────────────────────────────────────────────────────────────────
# Query Docker Hub pentru tags noi pe linia 19.0-YYYYMMDD
#─────────────────────────────────────────────────────────────────────────
echo "[check-odoo] Current pinned: $current_version"
echo "[check-odoo] Querying Docker Hub..."

tags=$(curl -fsSL "https://hub.docker.com/v2/repositories/library/odoo/tags?name=19.0&page_size=100" \
  | jq -r '.results | map(.name) | map(select(test("^19\\.0-[0-9]+$")))') \
  || { echo "ERROR: Docker Hub query failed" >&2; exit 1; }

latest=$(echo "$tags" | jq -r 'sort | reverse | .[0]')

if [[ "$latest" == "$current_version" ]]; then
  echo "[check-odoo] ✓ On latest version. Nothing to do."
  exit 0
fi

echo "[check-odoo] New version available: $latest (current: $current_version)"

#─────────────────────────────────────────────────────────────────────────
# Fetch changelog (best-effort din GitHub Odoo releases)
#─────────────────────────────────────────────────────────────────────────
fetch_changelog() {
  local from="$1"
  local to="$2"
  local from_date="${from#19.0-}"
  local to_date="${to#19.0-}"

  # Format Odoo: 19.0-YYYYMMDD → date pentru filtrare commits
  curl -fsSL "https://api.github.com/repos/odoo/odoo/compare/${from_date}...${to_date}" 2>/dev/null \
    | jq -r '.commits | map(.commit.message) | .[]' 2>/dev/null \
    || echo ""
}

changelog=$(fetch_changelog "$current_version" "$latest")
if [[ -z "$changelog" ]]; then
  echo "[check-odoo] ⚠ Changelog unavailable (compare API may not support these tags)."
  changelog="[changelog fetch failed — check manually]"
fi

#─────────────────────────────────────────────────────────────────────────
# Severity classifier — 3 niveluri pe baza changelog-ului upstream Odoo.
#
# Calibration history (update după primele 5-10 update-uri reale):
#   2026-05-06 — initial keywords (Sonnet 4.7 propose, validated)
#
# Pattern matching strategy: case-insensitive grep -E pe tot changelog-ul.
# False positive risk: comentarii sau test fixtures care conțin keywords.
# Acceptat fiindcă: better safe than sorry pe security + user reviewez
# manual înainte de merge (Renovate PR cu checklist).
#─────────────────────────────────────────────────────────────────────────

# Severity 30 — Security CVE / urgent
SEV30_PATTERN='CVE-[0-9]{4}-[0-9]+'
SEV30_PATTERN+='|[Ss]ecurity (fix|advisory|patch|issue)'
SEV30_PATTERN+='|[Vv]ulnerab(ility|le)'
SEV30_PATTERN+='|XSS|CSRF|SSRF|XXE'
SEV30_PATTERN+='|SQL.injection|command.injection'
SEV30_PATTERN+='|RCE|[Aa]rbitrary.code.execution'
SEV30_PATTERN+='|authentication.circumvent'
SEV30_PATTERN+='|privilege.escalation'
SEV30_PATTERN+='|[Ss]ecret (leak|exposure|disclosure)'

# Severity 20 — Business logic critical (RO fiscal + ecommerce flow)
SEV20_PATTERN='fix.*(invoice|tax|VAT|TVA|fiscal|ANAF|e.factura|SPV)'
SEV20_PATTERN+='|fix.*(account\.move|account\.payment|account\.tax)'
SEV20_PATTERN+='|fix.*(stock\.move|stock\.quant|stock\.picking)'
SEV20_PATTERN+='|fix.*(sale\.order|purchase\.order|product\.template)'
SEV20_PATTERN+='|fix.*(currency|exchange.rate)'
SEV20_PATTERN+='|fix.*payment'
SEV20_PATTERN+='|schema.migration'
SEV20_PATTERN+='|[Bb]reaking.change'
SEV20_PATTERN+='|deprecat(ed|ion)'

classify_update() {
  local changelog_text="$1"

  if echo "$changelog_text" | grep -qiE "$SEV30_PATTERN"; then
    echo "30"
    return
  fi

  if echo "$changelog_text" | grep -qiE "$SEV20_PATTERN"; then
    echo "20"
    return
  fi

  echo "10"
}

severity=$(classify_update "$changelog")

#─────────────────────────────────────────────────────────────────────────
# Output structured pentru cron-monitor → Telegram → GitHub
#─────────────────────────────────────────────────────────────────────────
case "$severity" in
  30)
    label="🚨 SECURITY CVE"
    ;;
  20)
    label="⚠️  MINOR (business logic)"
    ;;
  10)
    label="ℹ️  PATCH (low severity)"
    ;;
esac

cat <<REPORT
${label}
Current: $current_version
New:     $latest

Changelog (top 10 commits):
$(echo "$changelog" | head -10 | sed 's/^/  • /')

Action items:
  1. Review full changelog: https://github.com/odoo/odoo/compare/${current_version#19.0-}...${latest#19.0-}
  2. Run: scripts/update-odoo.sh --target $latest --dry-run
  3. If smoke test passes: scripts/update-odoo.sh --target $latest

REPORT

exit "$severity"
