# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Status repo

Customizare Odoo 19 Community pentru deployment la `erp.paff.ro` și integrare cu Medusa v2 la `paff.ro`.

**Setup inițial necesar (TODO la primul checkout):**
```bash
# Layer 1 — clone Odoo upstream READ-ONLY (vezi ADR 0001)
# Plus submodule OCA/l10n-romania pentru localizare
git clone --recurse-submodules <repo-url>
# SAU dacă deja ai clonat:
git submodule update --init --recursive

# Layer 1 source (read-only, doar pentru IDE/grep)
git clone --depth 1 --branch 19.0 https://github.com/odoo/odoo.git src/odoo

# Generate secrets în .env
cp config/env.template .env
scripts/generate-secrets.sh --update

# Build + start dev environment
docker compose up -d
docker compose logs -f odoo
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
│   ├── odoo/                    # READ-ONLY upstream (clone --depth 1 --branch 19.0)
│   ├── addons/                  # PAFF custom: paff_* (write freely)
│   └── addons-vendor/
│       └── l10n-romania/        # OCA submodule (l10n_ro_*, 29 module)
├── data/
│   ├── live/                    # PostgreSQL data dir (volume Docker)
│   ├── backup/                  # GFS retention: daily(7) / weekly(4) / monthly(60)
│   └── filestore/               # ⚠ Attachments PDF/imagini (NU în PG — backup separat)
├── config/
│   ├── odoo.conf                # workers, addons_path, env-substituted la entrypoint
│   └── env.template             # → cp config/env.template .env (gitignored)
├── docker/
│   ├── Dockerfile               # FROM odoo:19.0-YYYYMMDD@sha256:... + locale ro_RO + tz Europe/Bucharest
│   ├── entrypoint.sh            # envsubst odoo.conf + apply patches/ + wait postgres
│   └── healthcheck.sh           # /web/health verification
├── docker-compose.yml           # base config (Odoo + Postgres 17, networks, volumes)
├── docker-compose.override.yml  # dev: ports localhost, hot-reload addons (auto-loaded)
├── docker-compose.prod.yml      # prod: workers=4, 127.0.0.1 only, resource limits
├── scripts/
│   ├── init-db.sh               # creates DB + load lang ro_RO + install 17 module l10n_ro
│   ├── generate-secrets.sh      # openssl rand pentru .env (master_password, db_password)
│   ├── update-odoo.sh           # 8-test smoke suite + Dockerfile bump
│   ├── check-odoo-update.sh     # daily cron: severity classifier (CVE/business/patch)
│   ├── backup-db.sh             # pg_dump + tar filestore + GFS rotation
│   └── restore-db.sh            # cu safety prompt obligatoriu
├── patches/                     # Layer 2 — README.md + NNNN-titlu.{patch,md} per fiecare
├── docs/
│   ├── adr/                     # Architecture Decision Records
│   ├── deploy/                  # nginx-erp-paff-ro.conf.example, systemd-paff-odoo.service, deploy-checklist.md
│   ├── runbooks/                # upgrade.md, incident.md, deploy-vps.md
│   ├── templates/               # patch.md template
│   └── architecture.md
├── contracts/                   # OpenAPI/JSON Schema pentru Medusa↔Odoo port
├── tests/                       # Integration tests cross-system
├── logs/                        # gitignored
├── renovate.json                # Renovate Bot config (pinDigests + CVE alerts)
└── .claude/
    ├── settings.json            # Hook config
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

## Configuration Centralization (Architectural Rule)

**Regula PAFF #1 pentru addon-uri custom:** TOATE variabilele de configurare (peste toate addon-urile `paff_*`) trăiesc într-**UN SINGUR LOC** — atât în UI cât și în DB. Chiar dacă vor exista 5+ addon-uri custom (Telegram, ANAF, FAN Courier, NETOPIA, etc.), fiecare addon NU își creează propria pagină Settings + propria tabelă config.

### De ce regula
- **Discoverability** — admin caută o singură pagină pentru toate setările PAFF, nu să umble prin 5 meniuri
- **Audit/backup** — exporți o tabelă, nu N. Migrare între medii (dev/staging/prod) trivială
- **Consistency** — convenții naming uniforme: `paff_telegram_token`, `paff_anaf_endpoint`, `paff_fan_api_key` — același prefix, același store
- **DRY** — comune (timezone, default email, debug flag) declarate o dată

### Pattern technic (de validat în research R-002)

Două opțiuni în Odoo, decizia finală vine din research:

**A. `res.config.settings` extension cu prefix `paff_*`**
- Fiecare addon paff_X face `_inherit = 'res.config.settings'` și adaugă câmpuri cu prefix `paff_X_*`
- Toate apar în Settings → General Settings sub tab dedicat "PAFF Configuration"
- Stocate în `ir.config_parameter` cu key `paff_<addon>_<setting>`

**B. Model dedicat `paff.config` (singleton TransientModel sau Model)**
- Un singur model centralizat, toate addon-urile contribuie cu câmpuri prin `_inherit`
- O singură pagină în UI (ex: Settings → PAFF Configuration), cu tabs per addon
- Model query unitar: `env['paff.config'].get_param('telegram.token')`

Decizia se ia după **R-002** din `docs/research-backlog.md`. Până atunci, **NU implementa** addon-uri noi care își fac propria pagină Settings — așteaptă pattern-ul agreed.

### Reguli ferme până la R-002

- **NU** crea pagini Settings separate per addon (`paff_telegram` cu propriul tab Settings, `paff_anaf` cu altul, etc.)
- **NU** stoca credentials/tokens în câmpuri scattered prin model-uri (ex: `res.company.telegram_token`) — toate centralizate
- **DA** folosește `ir.config_parameter` direct cu prefix `paff_*` ca interim până se decide A vs B
- **DA** documentează fiecare variabilă nouă în `docs/configuration-vars.md` (TODO de creat la primul addon)

### Convenții naming

```
paff_<addon_short>_<setting>

Exemple:
  paff_telegram_bot_token
  paff_telegram_webhook_secret
  paff_anaf_api_endpoint
  paff_anaf_certificate_path
  paff_fan_api_key
  paff_netopia_signature_key
```

**NU**: `telegram_bot_token`, `paff.telegram.bot_token`, `TG_TOKEN` (mixed conventions = chaos)
**NU**: variabile fără prefix `paff_` (conflict potential cu Odoo core sau OCA)

### Secrets (token, API key, certificate password)

- **Sensitive vars**: stocate în `ir.config_parameter` cu Odoo encryption + acces restricted la `base.group_system`
- **Production**: alternativ, prin env var Docker (`.env`) → mai sigur (rotation Docker-managed) dar greu de UI-changed
- **Decizia finală** (DB-stored vs env-var) vine din R-002

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
- **NU crea pagini Settings/tabele config separate per addon** — vezi secțiunea `Configuration Centralization` (Regula PAFF #1)
- **NU folosi nume variabile fără prefix `paff_<addon>_*`** — naming convention obligatoriu cross-addon
- **NU instala module `website*`, `theme_*`, `mass_mailing`, `survey`** — PAFF e pure ERP (storefront e Medusa la paff.ro). Vezi [ADR 0003](docs/adr/0003-pure-erp-no-website.md). Excepție: ADR nou care anulează 0003.
- **NU declara `depends: ['website']`** în manifest paff_* addon — PR review reject automat. Pentru portal B2B (My Invoices) folosește `portal` care e instalat.

### Reguli ferme (ALWAYS)
- Manifest version: `"19.0.X.Y.Z"` (Odoo version + addon semver)
- `depends`: doar module care există în Odoo source (verifică cu `ls src/odoo/addons/`)
- `security/ir.model.access.csv`: o linie per model × group, NICIODATĂ access global fără rationale
- Vederi XML: `<tree>`, `<form>`, `<kanban>`, `<search>` — nu inline în Python
- Docstrings în română, cod în engleză
- Validări fiscale: cite ANAF API sau cui_registry (vezi `~/.claude/rules/research-agent-anti-hallucination.md` §5)
- Configuration vars: prefix `paff_<addon>_*` + stocare centralizată (vezi `Configuration Centralization`)
- Documentare config: orice variabilă nouă apare în `docs/configuration-vars.md` (lista master cross-addon)

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
# Generate secrets (prima dată)
cp config/env.template .env
scripts/generate-secrets.sh --update

# Start dev environment (auto-loads docker-compose.override.yml)
docker compose up -d

# Init DB cu localizare RO + 17 module l10n_ro (~5-10 min)
scripts/init-db.sh paff_dev

# Browser: http://localhost:8310 → login admin/admin (SCHIMBĂ parola)

# Logs live
docker compose logs -f --tail=100 odoo

# Update addon după modificări (paff_* sau OCA l10n_ro_*)
docker exec paff-erp-odoo \
  odoo -c /etc/odoo/odoo.conf \
       -u paff_<modul> \
       -d paff_dev \
       --stop-after-init

# Install addon nou
docker exec paff-erp-odoo \
  odoo -c /etc/odoo/odoo.conf \
       -i paff_<modul> \
       -d paff_dev \
       --stop-after-init

# Tests addon
docker exec paff-erp-odoo \
  odoo --test-enable \
       --stop-after-init \
       -d paff_test \
       -i paff_<modul> \
       --log-level=test

# Shell ORM debugging
docker exec -it paff-erp-odoo \
  odoo shell -d paff_dev --no-http
```

### Production (VPS)
```bash
# Detalii complete: docs/runbooks/deploy-vps.md
# Pre-flight checklist: docs/deploy/deploy-checklist.md

# Pe VPS, după setup inițial:
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Update routine
git pull origin main
git submodule update --remote --merge
docker compose -f docker-compose.yml -f docker-compose.prod.yml build odoo
sudo systemctl restart paff-odoo
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

| Mediu | URL | Container port → Host bind |
|---|---|---|
| Odoo dev | `http://localhost:8310` | `:8069` → `127.0.0.1:8310` |
| Odoo prod | `https://erp.paff.ro` (nginx VPS reverse proxy + Let's Encrypt) | `:8069` → `127.0.0.1:8310` |
| Odoo longpolling | `127.0.0.1:8312` | `:8072` → `127.0.0.1:8312` |
| PostgreSQL dev | NU expus pe host (Ecommerce monorepo ține range-ul 830x) | — |
| PostgreSQL prod | NU expus pe host (network paff-erp doar) | — |

- Master password Odoo: doar prin `.env` (NICIODATĂ în git)
- Generate cu: `scripts/generate-secrets.sh --update`
- **psql debugging**: `docker exec -it paff-erp-postgres psql -U odoo_user -d paff_prod` (NU expunem port pe host — evităm conflict permanent cu paff-postgres din Ecommerce monorepo, range 830x)
- Conflict port 8310 Odoo: dacă rulezi simultan cu Ecommerce monorepo + Odoo legacy, oprește acel container întâi (`cd ~/Work/Ecommerce && docker compose stop odoo`)

## TODO USER (locuri unde input-ul tău e valuable)

### Calibration după primele update-uri reale
- `scripts/check-odoo-update.sh` — funcția `classify_update()` cu pattern-uri default. Ajustează după primele 2-3 update-uri reale ce s-au făcut realmente PAFF (cuvinte specifice business, pragul minor vs patch)
- `scripts/update-odoo.sh` — funcția `run_smoke_test()` are 8 tests; adaugă tests funcționale (login admin, ANAF lookup) când rulezi în staging cu DB inițializată

### Workflow lunar declarații TVA (D300/D394) — manual prin SPV

L10n_ro Community NU exportă D300/D390/D394 direct (modul Enterprise feature). Workflow real:

1. **Final lună fiscală N** (până în 25 ale lunii N+1):
   - Odoo: Accounting → Reports → Tax Report → filter `Date Range = Month N` → click Export
   - Verifică totaluri: TVA colectat (21% sale), TVA deductibil (21% purchase), de plată/recuperat
2. **ANAF SPV** (browser cu USB token, NU programatic):
   - D300 — completează manual cu valorile din raport (cca 40 câmpuri)
   - D394 — upload XML facturi B2B (genere manual sau DUKIntegrator de la ANAF)
   - D390 — DOAR dacă există intracom (rar pentru PAFF cartoane)
3. **Înapoi în Odoo** (după ce ANAF acceptă declarația):
   - Settings → Accounting → set `Tax Lock Date = ultima zi luna N`
   - Asta blochează editare facturi din perioada deja declarată
4. **D406 SAF-T anual** (până 31 ianuarie pentru anul precedent):
   - Vezi R-008 în research-backlog: l10n_ro_saft third-party / DUKIntegrator / custom

⚠️ Lock date se setează DUPĂ confirmarea ANAF, NU înainte. Dacă ANAF cere modificări, ai nevoie să poți edita facturi din perioada respectivă.

### PRIMA factură reală — set name manual o singură dată
Sequence factură PAFF e configurat (journal Sales code='FAC', regex `FAC/PAFF\d{5}`), dar Odoo 19 NU oferă "starting number" config. La PRIMA factură creată în paff_prod:

1. Sales / Invoicing → Customers → Invoices → **+ New Invoice**
2. Adaugă partener client + linie produs
3. **ÎNAINTE de Confirm/Post**: editează câmpul `Number` (default va fi `Draft Invoice`) la **`FAC/PAFF12346`**
4. Click **Confirm** — invoice posted cu name `FAC/PAFF12346`
5. La a 2-a factură: Odoo detectează pattern-ul, auto-generează `FAC/PAFF12347`. Restul moștenesc.

⚠️ Dacă la pasul 3 lași numele default (`INV/2026/00001`), pattern-ul se rupe → reset sequence + lockdown manual ANAF compliance issue. **MUST be `FAC/PAFF12346` pe prima factură.**

Continuare numerotare (NU reset annually, NU date_range): factura 12345 din 2025 (alt software) → 12346 în Odoo, 12347... peste anii 2027, 2028...

## Reguli importante moștenite

- `~/.claude/CLAUDE.md` — workflow global (Plan First, Branch Management R1-R6, Package Management)
- `~/.claude/rules/paff-stack.md` — convenții stack PAFF (Medusa, Django, Odoo, Next.js)
- `~/.claude/rules/security-posture.md` — OWASP Agentic, secrets, supply chain
- `~/.claude/rules/architecture-principles.md` — Deep Modules + 4 categorii dependențe (Odoo = categoria 3)
- `~/.claude/rules/research-agent-anti-hallucination.md` §5 — date fiscale RO obligatoriu cu sursă
- `~/.claude/rules/docker-conventions.md` — `docker compose` v2, fără teardown distructiv

## Research backlog

Topice scoped dar neexecutate (research preliminar amânat):

- **R-001 Telegram integration** — 3 use cases (notificări outgoing + bot bidirecțional + approval workflow). Library aleasă: `python-telegram-bot v21+`. Self-hosted, decizie deschisă webhook vs polling.
- **R-002 Cross-addon shared config** — pattern Odoo pentru o singură pagină centrală + 1 tabelă DB pentru toate variabilele `paff_*`. **Architectural HIGH priority** — blochează design-ul oricărui nou addon.
- **R-003 VPS deploy gaps** — verificare runbook `deploy-vps.md` vs. realitate Ubuntu 24 OVH.

Detalii: [docs/research-backlog.md](docs/research-backlog.md). Format scoped (PROBLEMA / STACK / CE AM INCERCAT / CONSTRANGERI / plan execuție) ready pentru `/cauta` direct.

## Reference docs

- [Architecture overview](docs/architecture.md)
- [ADR 0001 — Three-Layer Isolation](docs/adr/0001-three-layer-isolation.md)
- [ADR 0002 — Upstream Pinning Policy](docs/adr/0002-upstream-pinning-policy.md)
- [ADR 0003 — Pure ERP, No Website](docs/adr/0003-pure-erp-no-website.md)
- [Runbook — Upgrade](docs/runbooks/upgrade.md)
- [Runbook — Incident](docs/runbooks/incident.md)
- [Runbook — Restore & DR](docs/runbooks/restore.md) — 4 scenarios (DB corrupt, filestore lost, code lost, full disaster) cu RTO/RPO targets
- [Patches workflow](patches/README.md)
- [Patch template](docs/templates/patch.md)
- [Permissions Matrix](docs/permissions-matrix.md) — 4 roluri (Vânzător/Operator, Contabil, Manager, Admin) + CRUD matrix + workflow approval + MFA policy
