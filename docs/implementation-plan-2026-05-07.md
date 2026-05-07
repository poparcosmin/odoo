# Implementation Plan v2 — PAFF Odoo 19 Production Readiness

> **Created:** 2026-05-07 v1 / **Revised:** 2026-05-07 v2 (post critique LLM Gemini + Codex)
> **Status:** APPROVED v2 — strategic A (5 phases, ~25-30h realist)
> **Source research:** `~/.claude/data/research/2026-05-07-odoo19-paff-hidden-gems.md`
> **Critique synthesis:** `~/.claude/data/plan-session/critique-2026-05-07/critique-synthesis.md`
> **Decision context:** zero-credit business model + no-NETOPIA + no-aging (memorie persistată)

## Changelog v1 → v2

- ✅ Added Phase 0 (Staging baseline) — BLOCKING per Gemini critical finding
- ✅ Added Phase 1.5 (Calibration) — post-baseline pentru B4 PG tuning
- ✅ Added Phase 4 (Manufacturing CAEN 1721) — DEFERRED scope
- ✅ Moved E8 (staging validation) → Phase 0 (was Phase 3)
- ✅ Moved T5 (Customer Portal) → Phase 3 (was Phase 2 — needs HTTPS public first)
- ✅ Moved B1 (workers) → Phase 3 (was Phase 1 — needs real VPS topology)
- ✅ Moved B4 (PG tuning) → Phase 1.5 (was Phase 1 — needs baseline first)
- ✅ Moved E4 (Chart of Accounts) → Phase 2 (was Phase 3 — pre-MIS Builder)
- ✅ Moved E7 (Export Rights) → Phase 2 (was Phase 3 — pre-Portal rollout)
- ✅ Re-estimated B5 (DB roles) 10min → 1.5-3h (10× underestimate)
- ✅ Re-estimated T4 (pricelist) 1h → 3-6h
- ✅ Re-estimated T7 (automations) 1h → 2-4h
- ✅ Re-estimated E5 (ANAF SPV cron) 1h → 4-8h
- ✅ Re-estimated E6 (audit log) 30min → 2-4h
- ✅ Added 11 missing items M1-M11 (observability, GDPR, security hardening, etc.)
- ✅ Fixed inconsistencies: D8 closed (duplicate B6), T7 contradicts zero-credit (rephrased)
- ✅ Total: 13h v1 → 25-30h v2

## Decizii NEW care BLOCHEAZĂ Phase 0

Critique-ul LLM a identificat 4 decizii care NU pot fi omise:

| ID | Decizie | Opțiuni |
|---|---|---|
| **DEC-A** | VPS dimension target | 4GB / 8GB / 16GB OVH |
| **DEC-B** | OCA 19.0 strategy | A wait OCA port / B pin 18.0 risk / C skip OCA custom |
| **DEC-C** | Staging environment | A separate DB same Docker / B separate VPS / C local laptop |
| **DEC-D** | Maintenance windows | declare upfront pentru B5 + Phase 3 deploy |

Plus close D8 (duplicate cu B6) și clarify T7 (rephrase pentru zero-credit).

---

## Phase 0 — Staging baseline (~1h) [NEW from BL1]

> Pre-validation OBLIGATORIU înainte orice fix prod. Without staging, fixurile sunt blind.

### P0.1 — VPS sizing inventory (15 min)

Pe VPS target (când e provisionat):
```bash
free -h           # RAM total + available
nproc             # CPU cores
df -h /          # Disk
docker version   # Docker installed?
```

Output: documentat în `docs/deploy/vps-sizing.md`. Determine values pentru B1 (workers) + B4 (PG tuning).

### P0.2 — Staging DB restore (15 min)

```bash
# Restore latest daily backup la nume separat
LATEST=$(ls -1dt data/backup/daily/paff_prod-* | head -1)
scripts/restore-db.sh "$LATEST" paff_staging

# Verify
docker exec paff-erp-postgres psql -U odoo_user -d paff_staging -c "
  SELECT 'staging_partner' as check, name FROM res_partner WHERE id = 1;
"
```

### P0.3 — Staging email + SPV disabled (10 min)

În staging DB (NU prod), update mail.server cu catchall + disable SPV:
- `mail.default.from = staging@noreply.paff.ro`
- Disable outgoing mail server temp
- ANAF SPV credentials NULL în staging

### P0.4 — Smoke test 4 roluri (30 min)

Activate temporar demo users (vanzator_demo, contabil_demo, manager_demo) — login fiecare în staging:
- Vânzător → create ofertă → confirm
- Contabil → vezi factură draft → POST → email send (catchall)
- Manager → view dashboard
- Admin → settings access

Rollback la final: deactivate demo users.

**Outputs Phase 0:**
- VPS sizing documentat
- Staging DB working baseline
- Smoke test passed pentru 4 roluri

**PR target:** `chore/staging-baseline` (docs only, no code change)

---

## Phase 1 — Config quick wins (~3-4h, was 2h)

> Modifications safe pe paff_prod (mostly 1-line config changes). B1 + B4 MUTATE post-baseline.

### B2 — `dbfilter=^paff_prod$` defense-in-depth (1 min)
- File: `config/odoo.conf` line nouă în `[options]`
- Why: dublu protection peste `list_db=False`

### B3 — `log_handler` uncomment (1 min)
- File: `config/odoo.conf` line 38
- Action: uncomment `log_handler = :INFO,werkzeug:WARNING,odoo.sql_db:WARNING`

### M3 — Observability minim (3h NEW)

PRECEDENCE pentru B6 (B6 fără M3 e doar query, nu alerting):

- Disk usage check (cron: `df -h | awk '$5+0 > 80'` → alert)
- RAM/CPU baseline (cron daily: `docker stats paff-erp-odoo --no-stream`)
- HTTP health (existing `/web/health` endpoint — verify cron probă)
- PostgreSQL connections (cron: `SELECT count(*) FROM pg_stat_activity` → alert dacă > 70)
- Backup freshness (already în notify.sh — verify recent < 26h)
- Certificate expiry (cert-renew check + alert at 14 zile)

Script nou: `scripts/health-monitor.sh` cu cron daily 09:00 → notify.sh.

### B6 — Scheduled actions monitoring (30 min, post-M3)

Folosind notify.sh existent + cron M3:

```sql
SELECT cron_name, active, failure_count
FROM ir_cron
WHERE failure_count > 0 OR (active = false AND failure_count >= 5);
```

→ alert Telegram + email dacă găsește.

### B5 — DB role separation (1.5-3h, REVISED 10× from 10 min)

**ATENȚIE: Maintenance window obligatoriu** (Odoo restart cere connection string change).

Steps:
1. Test pe staging FIRST:
   ```sql
   CREATE ROLE odoo_app LOGIN PASSWORD 'xxx';
   CREATE ROLE odoo_readonly LOGIN PASSWORD 'yyy';
   CREATE ROLE odoo_backup LOGIN PASSWORD 'zzz' REPLICATION;
   GRANT ALL ON SCHEMA public TO odoo_app;
   GRANT SELECT ON ALL TABLES IN SCHEMA public TO odoo_readonly;
   GRANT pg_read_all_data TO odoo_backup;
   -- Plus revoke superuser de la odoo_user existing
   ```
2. Update `.env` cu noi credentials
3. Restart Odoo, verify `-u all --stop-after-init` clean
4. Update `scripts/backup-db.sh` să folosească `odoo_backup` (NOT odoo_user)
5. Apply pe paff_prod ÎN maintenance window declarat (DEC-D)

### B7 — Filestore permissions audit (5 min)

```bash
docker exec paff-erp-odoo \
  find /var/lib/odoo/filestore/paff_prod -type d -not -perm 0700
# Should return empty
```

Add la verify-backup pipeline weekly.

### TODO USER paralel (Phase 1):
- **U1** Save age private key OFFLINE (Bitwarden) — 5 min
- **U2** Telegram bot setup @BotFather — 5 min
- **U3** Add `PAFF_TG_BOT_TOKEN` + `PAFF_TG_CHAT_ID` în `.env` — 1 min
- **U4** MFA enrollment Admin TOTP — 5 min

**PR target:** `chore/production-readiness-phase-1`

---

## Phase 1.5 — Calibration (~2h) [NEW]

> Measurement-driven tuning, NOT cargo cult.

### P1.5.1 — Baseline measurement (30 min)
- Run paff_prod 24h cu observability M3 active
- Collect: avg RAM, peak RAM, avg connections, slow queries

### P1.5.2 — B4 PG tuning calibrated (1h)

Calculate based on VPS sizing (DEC-A):
- 4GB VPS: shared_buffers=128MB, effective_cache_size=512MB, max_connections=40
- 8GB VPS: shared_buffers=256MB, effective_cache_size=1GB, max_connections=80
- 16GB VPS: shared_buffers=512MB, effective_cache_size=2GB, max_connections=120

Apply în `postgresql.conf` via volume mount sau `command:` în docker-compose.prod.yml.

### P1.5.3 — B1 workers planning (30 min, NOT applied yet)

Calculate workers per VPS sizing:
- 4GB VPS: workers=2 (memory_hard=1GB)
- 8GB VPS: workers=4 (memory_hard=1.5GB)
- 16GB VPS: workers=8 (memory_hard=2GB)

Document doar — apply în Phase 3 după VPS deploy.

**PR target:** `chore/calibration-phase-1.5`

---

## Phase 2 — Hidden gems + ETAPE (~8-10h, was 6h)

> Features high-ROI după baseline + monitoring stable.

### E2 — Payment Terms cleanup (15 min)
- Settings → Accounting → Payment Terms
- Disable T15/T30/T30 EOM/End of Month (păstrare istoric)
- Default sale.order: "Plată imediată"

### E1 + M6 — Pro-forma flow + livrare blocking rule (1h, was 30 min)
- Activate `sale.group_proforma_sales`
- **M6 NEW**: rule "confirmare producție/livrare DOAR după reconciliere bancară SAU override managerial audited"
  - Field nou pe sale.order: `payment_confirmed` (boolean)
  - Server action: blochează stock.picking confirm dacă `payment_confirmed=False`
  - Manager group has override authority cu mail.message log obligator
- Decision needed (D4): pro-forma numbering format

### E4 — Chart of Accounts customization (1h, MOVED FROM Phase 3)
- 614.PAFF — Cheltuieli producție carton
- 615.PAFF — Energie producție
- 707.PAFF.CRT — Vânzări carton
- 707.PAFF.AMB — Vânzări ambalaje finite
- 704.PAFF — Lucrări executate
- DEC: input cabinet contabilitate înainte
- **MOVED before T1**: MIS Builder reports built ON these accounts

### T1 + T2 + T3 — OCA modules (CONDITIONAL on DEC-B, 1.5h pe verificare)

ÎNAINTE submodule add — verify branch 19.0:
```bash
curl -s https://api.github.com/repos/OCA/account-financial-reporting/branches | jq '.[].name'
curl -s https://api.github.com/repos/OCA/web/branches | jq '.[].name'
```

Dacă **19.0 EXISTS**: install (1.5h)
Dacă **NU**: defer la `R-009 OCA 19.0 wait` (research backlog), use Tier 2 native config în loc

### T4 — 6-level pricelist + margin floors (3-6h, was 1h)
- 6 tier templates per research
- Margin floor logic — server action care reject sale.order line cu margin < 15%
- Test pe 5 produse demo

### T6 — Activity Types customizate PAFF (1h)
- 5 tipuri: verificare CIF, livrare șofer, încasare, vizită client, reconcile bank
- Chained activities (verificare CIF → trigger create offer)

### T7 — Automation Rules REVISED (2-4h, was 1h)

**FIX BL5**: rule "comenzi neîncasate" CONTRADICTS zero-credit. Rephrase:

1. `sale.order` confirm + amount > 50.000 RON → activity "Manager review"
2. `sale.order` cu pro-forma sent + `payment_confirmed=False` + age > 7 zile → activity Sales follow-up (NOT invoice posted!)
3. `stock.picking` done outgoing → SMS to client cu AWB
4. `res.partner` create + is_company → activity "Verify CIF ANAF in 24h"
5. `account.move` post (out_invoice) → schedule reconciliation check (NOT collection — factura emisă DUPĂ încasare în zero-credit)

### E7 — Export Rights (30 min, MOVED FROM Phase 3 — pre-Portal)
- `base.group_allow_export` → DOAR Admin + Contabil
- Max 1000 rows per export non-admin
- Audit log mail.message pe export action

### M4 — Outbound email safety (1h NEW)
- DKIM/SPF/DMARC pe `paff.ro` DNS zone
- Catchall pe staging (mail.catchall.domain = staging.paff.ro)
- Template review pro-forma + portal invitation
- DECISION: gestionare DNS (cui, când)

### M5 — GDPR/RO governance lightweight (1h NEW)
- Registru prelucrări — template în `docs/gdpr-records.md`
- DPA template (pentru cabinet contabilitate, FAN Courier viitor)
- DSAR procedure (Data Subject Access Request) — runbook scurt
- Retention policy attachments (5 ani fiscal RO)

**PR targets:**
- `feat/oca-bundle-phase-2` (CONDITIONAL pe DEC-B)
- `chore/native-config-phase-2` (E1, E2, E4, T4, T6, T7, E7, M4, M5)

---

## Phase 3 — VPS deploy + final (~6-8h, was 5h)

> Production deploy + ETAPE remaining + security hardening final.

### P3.1 — VPS provision + setup (1h)
- Ubuntu 24.04 LTS pe OVH (DEC-A size)
- Docker + Compose v2 install
- Git clone repo
- `.env` from age-encrypted backup (scripts/backup-env.sh --restore)

### P3.2 — Apply Phase 1.5 calibrations (30 min)
- B1 ODOO_WORKERS=N (per DEC-A sizing)
- B4 PG config from calibration

### P3.3 — VPS deploy actual (2h)
- nginx config from `docs/deploy/nginx-erp-paff-ro.conf.example` (existing template — production-ready)
- Let's Encrypt certbot pentru `erp.paff.ro`
- systemd service `paff-odoo.service`
- Firewall ufw (80/443/22 from admin IP whitelist)

### P3.4 — Post-deploy items

#### T5 — Customer Portal invite-only (30 min, MOVED FROM Phase 2)
- Settings → Sales → Pricelists → DISABLE "Show on website"
- Settings → Website → Customer Account → Invite-only
- Test cu vanzator_demo activat temporar (apoi deactivate)
- Decision needed (D3): scope full self-service / read-only / none

#### E3 — Sequences DVZ + STO (30 min)
- sale.order journal regex `^(?P<prefix1>DVZ/PAFF)(?P<seq>\d{5})$`
- Out_refund: separate journal "Sales Refund" code STO

#### E5 — Cron-uri custom (1h, post-monitoring)
- ANAF SPV refresh token (90 zile alert)
- mail.thread cleanup (5 ani retention enforce)
- res.partner duplicate detection (CIF unique)
- Each cron has alerting via B6 + M3

#### E6 — Audit Log + storage sizing (2-4h, was 30 min)
- `mail.activity.gc.delete_overdue_years = 5` (was 3)
- Verify mail.thread activ pe modele core
- Storage estimate: ~1MB/lună mail.message, 60MB/5 ani — OK
- Acces readonly via odoo_readonly role (din B5)
- Document compliance procedure în `docs/runbooks/audit-trail.md`

#### E8 — Final validation production (1h)
- Smoke test toate flows în paff_prod live
- Verify backup pipeline rulează la 03:00
- Test restore-test cron weekly
- Verify alerts Telegram + email

#### E9 — Incident Response Plan runbook (1h)
- New: `docs/runbooks/incident-response.md`
- Cover: DB corrupt, container crash, ANAF SPV down, Gmail OAuth expired, disk full
- RTO/RPO targets per scenariu
- Escalation: Cosmin → cabinet contabilitate → ANAF support

#### M7 — Security hardening post-deploy (1h NEW)
- fail2ban pentru SSH + nginx (rate limit auth attempts)
- SSH hardening: disable password auth, key-only
- unattended-upgrades pentru security patches Ubuntu
- sudo audit logs

#### M8 — Trivy vulnerability scan (30 min NEW)
- Scan Docker images existing (paff-odoo:local + postgres:18.3-alpine)
- Add Trivy step la GitHub Actions CI (când există)

#### M9 — Upgrade policy runbook (1h NEW)
- `docs/runbooks/upgrade-policy.md`
- Calendar: Odoo monthly check, OCA quarterly, PG yearly, Ubuntu weekly auto
- Rollback procedure per upgrade type

#### M10 — ANAF SPV operational (depinde de USB token user)
- Credential owner documented
- Certificate expiry calendar
- Retry/backoff în E5 cron
- Manual fallback procedure

**PR targets:**
- `chore/vps-deploy-phase-3` (P3.1, P3.2, P3.3)
- `feat/portal-and-sequences-phase-3` (T5, E3)
- `chore/operational-phase-3` (E5, E6, E8)
- `docs/runbooks-phase-3` (E9, M9)
- `chore/security-hardening-phase-3` (M7, M8)

---

## Phase 4 — Manufacturing CAEN 1721 (DEFERRED) [NEW M11]

> NU acum. După Phase 3 deploy + 30-60 zile operational data.

Trigger pentru reluare:
- ETAPA 3 real work completed (input portfoliu produse PAFF — categorii cartoane + produse reale)
- Nevoia de production planning concret (nu doar inventory)

Scope (DEFER):
- BOM design pentru cartoane plane / ondulate 3-strat / 5-strat
- Routing per mașină + work center capacity planning
- UoM specific carton (kg → mp → buc conversion ratios)
- Scrap tracking + loturi + serial numbers
- Cost sheet + marjă pe comandă
- Trasabilitate carton/ambalaje

Adaugă la `docs/research-backlog.md` ca **R-010 — Manufacturing CAEN 1721**.

---

## Total scope v2

```
Phase 0  Staging baseline       ~1h     (NEW)
Phase 1  Config quick wins      ~3-4h   (was 2h, B1+B4 moved out, M3 added)
Phase 1.5 Calibration            ~2h     (NEW)
Phase 2  Hidden gems + ETAPE    ~8-10h  (was 6h, +M4+M5+M6+E4+E7, T5 moved out)
Phase 3  VPS deploy + final     ~6-8h   (was 5h, +M7+M8+M9+T5+B1+B4 apply)
Phase 4  Manufacturing CAEN     ~?      (DEFERRED)
─────────────────────────────────────
TOTAL REVISED                   ~25-30h distribuit pe 4-5 sesiuni de ~5-6h each
```

**vs v1:** 13h → 25-30h (~70-130% underestimate corectat).

## Pre-implementation gates v2 (RESOLVED 2026-05-07)

| ID | Decizie | Status | Choice |
|---|---|---|---|
| **DEC-A** | VPS dimension target | ✅ RESOLVED | **8GB OVH** (sweet spot — workers=4 + PG tuning + buffer) |
| **DEC-B** | OCA 19.0 strategy | ✅ RESOLVED | **A. Wait OCA 19.0 port** — verify branch existence când ajungem la Phase 2; defer T1/T2/T3 ca R-009 dacă nu există |
| **DEC-C** | Staging environment | ✅ RESOLVED v2 | **A. Same Docker DB local** (REVISED 2026-05-07: VPS deferred la final) — staging temp pe acelaşi Docker stack ca paff_prod, separate DB `paff_staging`. Promote la separate VPS în Phase 3 final |
| **DEC-D** | Maintenance windows | ✅ RESOLVED | **Sunday 02:00-04:00 RO** — zero traffic B2B (cabinet contabilitate + vânzători nu lucrează) |
| ~~D8~~ | ~~Scheduled action monitoring~~ | ✅ closed | duplicate cu B6 |
| **D3** | Customer portal scope | ⏳ deferred | rezolvăm la Phase 3 când ajungem la T5 |
| **D4** | Pro-forma numbering | ⏳ deferred | rezolvăm la Phase 2 când ajungem la E1 |
| **D5** | Volume commitment trigger | ⏳ deferred | rezolvăm la Phase 2 când ajungem la T4 |
| **D6** | Activity Types timing | ⏳ deferred | rezolvăm la Phase 2 când ajungem la T6 |
| **D7** | DB role separation timing | ⏳ deferred | rezolvăm la Phase 1 când ajungem la B5 |

### Implications DEC-C revizat — Docker local staging

User decision 2026-05-07: VPS deferred la Phase 3 final. Folosim **Docker local staging temp** acum.
- **P0.0 SKIP** — no VPS provision needed acum
- **P0.1 SKIP** — VPS sizing inventory deferred la Phase 3
- **P0.2-P0.4 active** pe acelaşi Docker stack (`paff_staging` DB pe paff-erp-postgres existing)
- Phase 3 VPS deploy = unicul loc unde VPS apare; promotion la separate VPS atunci

Trade-offs acceptate:
- ✅ Phase 0 + 1 + 2 pot avansa imediat fără cost extra
- ⚠️ Risc minim: paff_staging DB ON same Docker = un postgres crash afectează ambele. Mitigare: backup pipeline existent (3-2-1 cu Google Drive) + monthly verify-backup
- ⚠️ Phase 3 VPS deploy va trebui re-validate în staging real VPS atunci

## Cross-references

- Research raport: `~/.claude/data/research/2026-05-07-odoo19-paff-hidden-gems.md`
- Critique synthesis: `~/.claude/data/plan-session/critique-2026-05-07/critique-synthesis.md`
- Memorie zero-credit: `~/.claude/projects/-home-cosmin-Work-Odoo/memory/project_paff_no_credit_sales.md`
- Permissions matrix: `docs/permissions-matrix.md`
- Backup runbook: `docs/runbooks/restore.md`
- Research backlog: `docs/research-backlog.md`
- nginx config template: `docs/deploy/nginx-erp-paff-ro.conf.example`

## Status tracking v2

Update acest fișier la final de fiecare phase cu:
- ✅ Items completate (cu commit hash + PR #)
- 🟡 Items în progres
- ❌ Items skipped (cu rationale)
- 📋 Items deferred la next phase

### Decisions log

| Date | Decision | Choice | Rationale |
|---|---|---|---|
| 2026-05-07 | zero-credit business model | confirmed | user policy decision |
| 2026-05-07 | NETOPIA Payments | skip | bank transfer only |
| 2026-05-07 | strategic A 3-phase v1 | approved | initial plan |
| 2026-05-07 | strategic A 5-phase v2 | approved | post critique LLM |
| 2026-05-07 | DEC-A VPS dimension | 8GB OVH | sweet spot prod usage |
| 2026-05-07 | DEC-B OCA 19.0 strategy | wait + defer if no 19.0 branch | safety > velocity |
| 2026-05-07 | DEC-C staging environment | separate VPS 4GB | fidelity max, zero corupție prod |
| 2026-05-07 | DEC-D maintenance windows | Sunday 02:00-04:00 RO | zero traffic B2B carton |
