#!/bin/bash
# src-odoo-readonly-guard.sh
# PreToolUse hook care blochează scrierea în src/odoo/** (upstream pur, read-only).
#
# Layer 1 din Three-Layer Isolation (vezi docs/adr/0001-three-layer-isolation.md).
# Modificările trebuie să meargă în src/addons/ (preferat) sau patches/ (excepție).
#
# Hook config în .claude/settings.json:
#   {"matcher": "Edit|Write", "hooks": [{"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/src-odoo-readonly-guard.sh"}]}

set -euo pipefail

# Citește input JSON din stdin (formatul Claude Code hooks)
input=$(cat)

# Extract file_path din tool_input
file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')

if [[ -z "$file_path" ]]; then
  exit 0
fi

# Normalizează path la absolute
abs_path="$file_path"
if [[ "${abs_path:0:1}" != "/" ]]; then
  abs_path="${CLAUDE_PROJECT_DIR:-$PWD}/$file_path"
fi

# Detectează scriere în src/odoo/
if [[ "$abs_path" == *"/src/odoo/"* ]] || [[ "$abs_path" == */src/odoo ]]; then
  cat >&2 <<MESSAGE
╔══════════════════════════════════════════════════════════════════════╗
║  ⛔ BLOCKED: src/odoo/ is READ-ONLY (upstream pur)                    ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  File:  $file_path
║                                                                      ║
║  src/odoo/ e clonat strict ca referință pentru IDE/grep/debugging.   ║
║  Customizările PAFF se fac peste, nu în interior.                    ║
║                                                                      ║
║  Alternative:                                                        ║
║                                                                      ║
║    1. ✅ Addon nou/inheritance (99% din cazuri):                     ║
║       → src/addons/paff_<modul>/ cu _inherit ORM sau xpath views     ║
║                                                                      ║
║    2. ✅ Patch documented (cazuri excepționale):                     ║
║       → patches/NNNN-titlu.patch + patches/NNNN-titlu.md             ║
║       → vezi docs/templates/patch.md pentru convenția obligatorie    ║
║                                                                      ║
║    3. ❌ NU modifica direct în src/odoo/                              ║
║       Pierzi toate schimbările la următorul "git pull upstream".     ║
║                                                                      ║
║  Detalii: docs/adr/0001-three-layer-isolation.md                     ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
MESSAGE
  exit 2
fi

exit 0
