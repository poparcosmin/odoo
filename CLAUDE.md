# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Status repo

Customizare Odoo 19 Community pentru deployment la `erp.paff.ro` și integrare cu Medusa v2 la `paff.ro`.

**Setup inițial necesar (TODO la primul checkout):**
```bash
# Layer 1 — clone Odoo upstream READ-ONLY (vezi ADR 0001)
git clone --depth 1 --branch 19.0 https://github.com/odoo/odoo.git src/odoo

# Pin digest la primul build (vezi ADR 0002)
docker pull odoo:19.0
docker inspect odoo:19.0 | jq -r '.[0].RepoDigests[0]'
# Copiază digest-ul în docker/Dockerfile (ARG ODOO_DIGEST)

# Copiază env template
cp config/env.template .env
# Completează valorile reale (master password, DB credentials, etc.)
```

## Three-Layer Isolation (Architecture)

```
┌──────────────────────────────────────────────────────────────┐
│  LAYER 3: src/addons/  — WRITE FREELY                        │
│  ├── paff_*           Business logic via _inherit ORM        │
│  ├── l10n_ro_*        OCA modules (NU modifica)              │
│  └── extensions/      Monkey-patches în __init__.py          │
├──────────────────────────────────────────────────────────────┤
│  LAYER 2: patches/    — DOCUMENTED EXCEPTIONS ONLY           │
│  ├── 0001-foo.patch   Diff aplicat la container build        │
│  ├── 0001-foo.md      Justificare + sunset criteria          │
│  └── README.md        Convenția de nume + workflow           │
├──────────────────────────────────────────────────────────────┤
│  LAYER 1: src/odoo/   — READ-ONLY (enforced by hook)         │
│  └── upstream pur     Niciodată Edit/Write aici              │
│                       Folosit DOAR pentru IDE/grep/debug     │
└──────────────────────────────────────────────────────────────┘
```

**Regula de aur:** dacă Layer 3 (addon override) poate rezolva problema → mergi acolo. Dacă nu poate → Layer 2 cu documentare obligatorie. **Layer 1 e sacru** — hook-ul `.claude/hooks/src-odoo-readonly-guard.sh` blochează scrierea la nivel de PreToolUse.

Detalii: [docs/adr/0001-three-layer-isolation.md](docs/adr/0001-three-layer-isolation.md)

## Folder Layout

```
/home/cosmin/Work/Odoo/
├── src/
│   ├── odoo/              # READ-ONLY upstream (clone --depth 1 --branch 19.0)
│   └── addons/            # PAFF custom: paff_*, l10n_ro_*
├── data/
│   ├── live/              # PostgreSQL data dir (volume Docker)
│   ├── backup/            # GFS retention: daily(7) / weekly(4) / monthly(60)
│   └── filestore/         # ⚠ Attachments PDF/imagini (NU în PG — backup separat)
├── config/
│   ├── odoo.conf          # workers, addons_path, env-substituted
│   ├── env.template       # → copy to .env (gitignored)
│   └── caddy/Caddyfile    # erp.paff.ro proxy + HTTPS + HSTS
├── docker/
│   ├── Dockerfile         # ARG ODOO_VERSION + ARG ODOO_DIGEST (pinned)
│   ├── entrypoint.sh      # apply patches/ + wait postgres
│   └── healthcheck.sh     # /web/health verification
├── scripts/
│   ├── update-odoo.sh     # ⚠ TODO USER: smoke test conditions (vezi script)
│   ├── check-odoo-update.sh  # ⚠ TODO USER: severity classifier (vezi script)
│   ├── backup-db.sh       # pg_dump + tar filestore + GFS rotation
│   └── restore-db.sh      # cu safety prompt obligatoriu
├── patches/               # Layer 2 — README.md + .patch + .md per fiecare
├── docs/
│   ├── adr/               # Architecture Decision Records
│   ├── runbooks/          # upgrade.md, incident.md
│   ├── templates/         # patch.md template
│   └── architecture.md
├── contracts/             # OpenAPI/JSON Schema pentru Medusa↔Odoo port
├── tests/                 # Integration tests cross-system
├── logs/                  # gitignored
├── renovate.json          # Renovate Bot config (pinDigests + CVE alerts)
└── .claude/
    ├── settings.json      # Hook config
    └── hooks/src-odoo-readonly-guard.sh
```

## Upgrade Discipline (Odoo Upstream)

### Pinning Policy

**INTERZIS:**
- ❌ `odoo:latest`
- ❌ `odoo:19` (major track, mutabil)
- ❌ `odoo:19.0` (minor track, mutabil)

**OBLIGATORIU:**
- ✅ `odoo:19.0-YYYYMMDD@sha256:<digest>` (calendar version + content-addressed digest)

Rationale și mecanism: [docs/adr/0002-upstream-pinning-policy.md](docs/adr/0002-upstream-pinning-policy.md)

### Alerting (3 layere)

1. **Renovate Bot** (primary) — `renovate.json` pinDigests + vulnerabilityAlerts. PR auto-creat cu changelog + checklist obligatoriu
2. **Cron monitor PAFF** (backup) — `scripts/check-odoo-update.sh` rulat zilnic 07:00 RO → Telegram via skill `tg`
3. **GitHub issue auto-create** pentru severity ≥ 20 (minor/security)

### Severity levels

| Nivel | Trigger | Channel | SLA |
|-------|---------|---------|-----|
| 30 — Security CVE | `CVE-`, `security`, `XSS`, etc. | Telegram urgent + GitHub issue `urgent` | < 24h staging |
| 20 — Minor (business) | `fix` + cuvinte fiscale (`invoice`, `tax`, `VAT`, `ANAF`) | Telegram + GitHub issue | < 7 zile |
| 10 — Patch (low) | Restul | Weekly digest | < 30 zile |

### Update flow

```bash
# Recomandat: prin script (smoke test included)
scripts/update-odoo.sh --target 19.0-YYYYMMDD --dry-run
scripts/update-odoo.sh --target 19.0-YYYYMMDD

# SAU prin Renovate PR review + merge
```

⚠ **NU modifica manual** `docker/Dockerfile` cu version+digest fără rulare smoke test.

## Convenții Odoo 19 (PAFF)

### Structura addon-urilor custom (`src/addons/paff_*`)
```
paff_<modul>/
├── __init__.py
├── __manifest__.py        # name, version "19.0.X.Y.Z", depends, data, assets
├── controllers/           # HTTP routes (XML-RPC, REST custom)
├── data/                  # XML data files (cron, demo, default records)
├── models/                # Python ORM models (snake_case)
├── report/                # QWeb PDF reports
├── security/              # ir.model.access.csv + record rules
├── static/src/{js,css,xml}/  # Owl 2 (NU jQuery legacy)
├── views/                 # XML — tree, form, kanban, search
└── wizard/                # transient.model dialogs
```

### Reguli ferme (NEVER)
- **NU modifica `src/odoo/`** — hook-ul blochează structural; alternativă: addon `_inherit` sau patch
- **NU modifica modulele `l10n_ro_*`** — sunt OCA, submite PR upstream sau extinde prin moștenire
- **NU folosi raw SQL** în models — folosește ORM, `cr.execute()` doar pentru migrări/performance cu comment
- **NU hardcoda CIF/TVA/curs valutar** — folosește `res.config.settings` sau ANAF API
- **NU instala dependencies cu `pip` în container** — adaugă în `docker/Dockerfile`

### Reguli ferme (ALWAYS)
- Manifest version: `"19.0.X.Y.Z"` (Odoo version + addon semver)
- `depends`: doar module care există în Odoo source (verifică cu `ls src/odoo/addons/`)
- `security/ir.model.access.csv`: o linie per model × group, NICIODATĂ access global fără rationale
- Vederi XML: `<tree>`, `<form>`, `<kanban>`, `<search>` — nu inline în Python
- Docstrings în română, cod în engleză
- Validări fiscale: cite ANAF API sau cui_registry (vezi `~/.claude/rules/research-agent-anti-hallucination.md` §5)

## Integrare Medusa ↔ Odoo

- **Pattern:** Ports & Adapters (categoria 3 "Remote but owned")
- **Protocol:** JSON-RPC 2.0 sau XML-RPC (Odoo expune ambele)
- **Eventual consistency:** sync-ul NU e real-time
- **Validează MEREU răspunsurile Odoo** — failează silent (returnează `False` în loc de exception)
- **Skill PAFF dedicat:** `odoo-integration` — invocare prin trigger phrases ("Odoo", "JSON-RPC", "sincronizeaza cu odoo")
- **Contracts:** definiții schema în `contracts/` (sursă de adevăr pentru ambele părți)

## Comenzi uzuale

### Dezvoltare locală
```bash
# Start Odoo
docker compose --profile erp up -d odoo

# Logs live
docker compose logs -f --tail=100 odoo

# Update addon după modificări
docker exec -it paff-odoo \
  odoo -c /etc/odoo/odoo.conf \
       -u paff_<modul> \
       -d <db_name> \
       --stop-after-init

# Install addon nou
docker exec -it paff-odoo \
  odoo -c /etc/odoo/odoo.conf \
       -i paff_<modul> \
       -d <db_name> \
       --stop-after-init

# Tests addon
docker exec -it paff-odoo \
  odoo --test-enable \
       --stop-after-init \
       -d <db_test> \
       -i paff_<modul> \
       --log-level=test

# Shell ORM debugging
docker exec -it paff-odoo \
  odoo shell -d <db_name> --no-http
```

### Backup & Restore
```bash
# Backup zilnic (auto via cron)
scripts/backup-db.sh paff_prod --type daily

# Backup săptămânal/lunar
scripts/backup-db.sh paff_prod --type weekly
scripts/backup-db.sh paff_prod --type monthly

# Restore (cu safety prompt)
scripts/restore-db.sh data/backup/daily/paff_prod-YYYYMMDD-HHMMSS paff_test
```

### Upgrade upstream
```bash
# Check pentru update-uri
scripts/check-odoo-update.sh

# Apply update (cu smoke test)
scripts/update-odoo.sh --target 19.0-YYYYMMDD --dry-run
scripts/update-odoo.sh --target 19.0-YYYYMMDD
```

### Update src/odoo/ (READ-ONLY pull)
```bash
cd src/odoo
git pull origin 19.0   # mereu clean — n-ai modificat nimic
```

## Tooling repo

- **Python:** `uv` (NU `pip` direct) — `uv pip install -e .` pentru dev install
- **Linting:** `uvx ruff check src/addons/paff_*`
- **Type checks:** `uvx mypy --ignore-missing-imports src/addons/paff_*`
- **Pre-commit:** `uvx pre-commit run --all-files`

## Mediu și porturi

- Odoo dev: `http://localhost:8310` (host) → `:8069` (container)
- Odoo prod: `https://erp.paff.ro` (Caddy reverse proxy + Let's Encrypt)
- Odoo longpolling: port `8312` (host) → `:8072` (container)
- PostgreSQL: `localhost:8301` — DB Odoo separat de DB Medusa (NU partaja schema)
- Master password Odoo: doar prin `.env` (NICIODATĂ în git)

## TODO USER (locuri unde tu definești comportamentul)

Două locuri unde input-ul tău shape-uiește feature-ul:

### 1. Smoke test conditions — `scripts/update-odoo.sh`
Funcția `run_smoke_test()` are TODO marker pentru:
- Threshold timeout startup (default 60s)
- Asserții suplimentare după health endpoint (login admin? l10n_ro install? ANAF lookup?)

### 2. Severity classifier — `scripts/check-odoo-update.sh`
Funcția `classify_update()` are keywords default. Ajustează după primele 2-3 update-uri reale:
- Adaugă cuvinte specifice business PAFF
- Calibrează pragul "minor vs patch" pe ce vezi tu critic

## Reguli importante moștenite

- `~/.claude/CLAUDE.md` — workflow global (Plan First, Branch Management R1-R6, Package Management)
- `~/.claude/rules/paff-stack.md` — convenții stack PAFF (Medusa, Django, Odoo, Next.js)
- `~/.claude/rules/security-posture.md` — OWASP Agentic, secrets, supply chain
- `~/.claude/rules/architecture-principles.md` — Deep Modules + 4 categorii dependențe (Odoo = categoria 3)
- `~/.claude/rules/research-agent-anti-hallucination.md` §5 — date fiscale RO obligatoriu cu sursă
- `~/.claude/rules/docker-conventions.md` — `docker compose` v2, fără teardown distructiv

## Reference docs

- [Architecture overview](docs/architecture.md)
- [ADR 0001 — Three-Layer Isolation](docs/adr/0001-three-layer-isolation.md)
- [ADR 0002 — Upstream Pinning Policy](docs/adr/0002-upstream-pinning-policy.md)
- [Runbook — Upgrade](docs/runbooks/upgrade.md)
- [Runbook — Incident](docs/runbooks/incident.md)
- [Patches workflow](patches/README.md)
- [Patch template](docs/templates/patch.md)
