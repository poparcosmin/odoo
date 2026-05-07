# Research Backlog — PAFF Odoo

> Topice de cercetat înainte de implementare. Fiecare entry are scope complet
> definit (PROBLEMA / STACK / CE AM INCERCAT / CONSTRANGERI) ready pentru
> `/cauta` execuție directă, fără re-interview.
>
> Workflow: când e timpul să implementezi, copiază scope-ul + rulează `/cauta`
> cu argumentele preserved. Output ajunge in `~/.claude/data/research/<slug>.md`,
> apoi `/plan-session` pentru plan + critique.

---

## R-000 — Pre-launch Configuration Checklist Odoo 19 (PAFF SRL B2B RO) ✅ EXECUTED

**Status:** executed (2026-05-06), with dual-LLM critique
**Priority:** HIGH (blocking pentru go-live)
**Outputs:**
- `~/.claude/data/research/2026-05-06-odoo19-pre-launch-checklist-v1.md` (initial research)
- `~/.claude/data/research/2026-05-06-odoo19-pre-launch-checklist-v2.md` (v2 + critique fixes)

### Key findings

- **14 etape** (vs 9 în v1) cu ~120 setting points
- **3 erori critice corectate** post-critique:
  - ANAF USB token (one-time browser, NU operational)
  - Chart of Accounts IFRS (illegal pentru SRL — doar PlanConturiBalSocCom)
  - Custom security groups iterative (must fi UP-FRONT)
- **5 etape NEW** identificate de critique:
  - ETAPA 0 — Security Hardening (admin lifecycle, MFA, session)
  - ETAPA 2-bis — TVA la încasare + BNR cron (B2B valută)
  - ETAPA 3-bis — E-Factura Inbound + OAuth lifecycle (token 90 zile)
  - ETAPA 10 — Audit Log Extensiv (5 ani RO compliance)
  - ETAPA 11 — Export Rights & Exfiltration Controls
  - ETAPA 12 — Backup VERIFIED (restore test mandatory)
  - ETAPA 14 — Incident Response Plan
- **Verdict comun (Gemini + Codex):** NU lansa cu v1 — era configurare funcțională, NU readiness producție

### Next consume

V2 e seed pentru `/plan-session` sau `/paff-plan`. Începe execuția cu ETAPA 0 (Security Hardening) ca prerequisite.

---

## R-001 — Integrare Telegram în Odoo (3 use cases)

**Status:** scoped, awaiting execution
**Created:** 2026-05-06
**Priority:** medium (post-deploy VPS, post-config PAFF SRL)
**Estimated research effort:** 3-5 min (10 calls paralel)

### Scope

```
PROBLEMA: Integrare Telegram in Odoo 19 (3 use cases combinate)
  1. Notificări outgoing — Odoo → Telegram (orders, invoices, stock alerts)
  2. Bot bidirectional — Telegram → Odoo (comenzi /stoc, /factura) +
     Odoo → Telegram (răspuns)
  3. Aprobări workflow — notificări cu Inline Keyboard (Approve/Reject)
     → state Odoo updated

STACK:
  - Odoo 19.0-20260504 (Python 3.12)
  - PostgreSQL 18.3-alpine
  - Docker (paff-erp-net network)
  - python-telegram-bot v21+ (library aleasă)

CE AM ÎNCERCAT: N/A — research preliminar, bot dedicat nou
  (NU reuse skill `tg` din ~/.claude/skills/, deși există)

CONSTRANGERI:
  - Self-hosted (container Odoo SAU service separat în docker-compose)
  - Compat Odoo 19 + Docker
  - Webhook vs polling — DECIZIE DESCHISĂ (depinde de erp.paff.ro HTTPS public)
  - Cross-cutting PAFF: variabilele de config în 1 singur loc (vezi R-002)

CUTOFF: 2024-11-06 (18 luni, non-volatile topic)
```

### Plan de executie (când rulezi)

```
1. Pilot WebSearch: "Odoo 19 telegram bot integration python 2026"
2. context7 query-docs python-telegram-bot — async patterns
3. WebSearch "Telegram Bot API webhook self-hosted Docker 2026"
4. WebSearch "OCA telegram OR mail-telegram github" — module-uri existente
5. WebSearch "python-telegram-bot Inline Keyboard callback workflow"
6. WebSearch "Odoo cron telegram notification stock alert" — patterns
7. WebFetch top 3 hits din Pilot — extract content
8. Agent Oracle PAFF — coexistență cu skill `tg`
9. WebSearch "Odoo addon long-running service docker-compose" — bot lifecycle
10. WebSearch "Telegram Bot API rate limit retry exponential backoff"
```

### Decizii probabil deschise (de pus în plan după research)

- **Bot lifecycle**: process în container Odoo (thread/cron) vs. service Docker separat (`paff-erp-telegram-bot`)?
- **Webhook URL**: `https://erp.paff.ro/telegram/webhook/<secret>` (necesită Odoo public) vs. polling (nu cere public)?
- **Token storage**: `ir.config_parameter` (encrypted by Odoo) vs. env var în Docker (mai sigur, mas greu de UI-changed)?
- **Routing per role**: 1 chat global vs. multiple chat-uri per Odoo group (sales, accounting, admin)?
- **Approval flow security**: callback Telegram → Odoo cere autentificare? Cum mapezi `telegram_user_id` → `res.users`?

### Trigger pentru execuție

```
/cauta cum putem integra telegram in Odoo --research-driven
# (sau copiază scope-ul de mai sus și rulează /cauta direct cu el ca seed)
```

---

## R-002 — Cross-addon shared configuration page (architectural)

**Status:** scoped, awaiting execution
**Created:** 2026-05-06
**Priority:** HIGH (arhitectural, blochează design pentru toate paff_* addons)
**Estimated research effort:** 2-3 min (6 calls paralel)

### Context

User constraint declarat în R-001 dar applicable pentru TOATE viitoarele addon-uri PAFF:

> "O singură pagină centrală pentru toate variabilele config — chiar dacă avem
> 5 addons `paff_*`, toate variabilele scrise într-un singur loc. O singură
> pagină de afișat, o singură tabelă în DB pentru a scrie în ea."

### Scope

```
PROBLEMA: Pattern Odoo pentru a centraliza configurarea cross-addon.
  Toate addon-urile paff_* (telegram, inventar_carton, fiscal, etc.) trebuie
  să-și citească variabilele dintr-un singur loc UI + DB.

  Anti-pattern de evitat: fiecare addon are propria pagină Settings cu
  res.config.settings extension separat, configurări duplicate, chei diferite
  (paff.telegram.token vs paff_telegram_token vs telegram_bot_token).

STACK:
  - Odoo 19 ORM
  - res.config.settings (Settings page extension)
  - ir.config_parameter (key-value store)
  - Mecanisme custom model (ex: paff.config singleton TransientModel sau Model)

CE AM ÎNCERCAT: N/A — research arhitectural înainte de a începe primul addon

CONSTRANGERI:
  - Tot stack-ul PAFF trebuie să folosească același pattern (consistency)
  - Configurările secrete (token, API keys) trebuie să fie criptat sau via env
  - Pattern-ul trebuie să suporte adăugare incrementală de variabile
    (când scriu addon nou, adaug câmp, NU model nou)
  - Compat cu reload Docker (env-substituted vs. DB-stored)

CUTOFF: 2023-05-06 (3 ani, Odoo patterns sunt stabile)
```

### Plan de executie (când rulezi)

```
1. context7 query-docs Odoo res.config.settings
2. WebSearch "Odoo res.config.settings inherit multiple modules pattern"
3. WebSearch "Odoo ir.config_parameter vs res.config.settings best practice"
4. WebSearch "OCA configuration_helper OR shared_settings github" — există?
5. WebSearch "Odoo 19 secrets management env var vs database"
6. Agent Oracle PAFF — sugestie arhitectură pentru constraint user
```

### Decizii probabil deschise

- **Singleton model `paff.config`** vs. **`res.config.settings` extension cu prefix `paff_*`**?
- **Secrets în `ir.config_parameter`** (Odoo encrypts but visible to admin) vs. **doar env var** (Docker-managed, audit prin docker config)?
- **Model UI**: 1 form lung cu toate setările, sau **tabs pe addon** (Telegram tab, Fiscal tab, etc.)?
- **Backup/restore**: cum se exportă/importă config-ul între medii (dev/staging/prod)?

### Output expected pentru raport

- Pattern code-ready (clasă model + view XML pentru tab-uri)
- Convenții naming (prefix `paff_*`, group-uri `paff.config_group_telegram`, etc.)
- Migrare strategy dacă în viitor volume mare → schema dedicată

---

## R-003 — VPS deploy first run pe `erp.paff.ro` (când vine timpul)

**Status:** scoped, awaiting execution dependency (deploy ready)
**Created:** 2026-05-06
**Priority:** medium (după PAFF SRL company config done)
**Doc existent:** `docs/runbooks/deploy-vps.md` (acoperă major)

### Scope

```
PROBLEMA: Verificare gap-uri în runbook deploy-vps.md vs. realitate VPS OVH.
  Runbook scris speculativ — research valida pentru OVH-specific quirks.

STACK:
  - Ubuntu 24 LTS (OVH VPS)
  - Docker + Compose v2 (instalate)
  - Nginx (configurat pentru alte domenii)
  - Let's Encrypt + certbot (auto-renewal active)

CE AM ÎNCERCAT: Runbook scris în Phase 4 a setup-ului (vezi
  docs/runbooks/deploy-vps.md). Nu e încă executat pe VPS real.

CONSTRANGERI:
  - SSH alias `ovh` configurat
  - Path target: `~/web/erp.paff.ro/`
  - Coexistență cu alte servicii (alte domenii) pe nginx
```

### Plan de executie

```
1. WebSearch "OVH VPS Ubuntu 24 docker compose systemd best practice 2026"
2. WebSearch "nginx reverse proxy odoo 19 multiple sites letsencrypt"
3. WebSearch "docker compose production logs rotation systemd journal"
4. Agent Oracle — verifică runbook-ul actual pe edge cases OVH
```

---

## R-004 — Mass Mailing + Survey Modules (DEFERRED ~2027)

**Status:** deferred per ADR 0003 (decizie utilizator 2026-05-07)
**Priority:** low (nu blocking, evaluare after Medusa go-live + 1 an)
**Decision date target:** Q1 2027 (after primii 12 luni B2B operational data)

### Context

La uninstall website* (per ADR 0003), s-au evaluat și module-urile:
- `mass_mailing` (newsletter campaigns)
- `survey` (post-purchase / NPS surveys)

Decizie: **NU instalăm acum**, dar nu blocăm pentru viitor. User a indicat: *"o sa le folosim, nu acum, dar peste 1 an probabil le vom folosi"*.

### Re-evaluation criteria (Q1 2027)

```
PROBLEMA: PAFF SRL are 12 luni de date B2B operational (ANAF e-Factura logged,
  comenzi Medusa logged, customer base ~50-200 B2B clients). Vrem să decidem
  dacă canalul de email marketing rulează din Odoo (mass_mailing native) sau
  through SaaS extern (Mailchimp, Postmark, Resend already used pentru transactional).

STACK:
  - Odoo 19 fără website* modules (per ADR 0003)
  - Medusa storefront paff.ro (transactional emails via Resend already)
  - Customer data în Odoo res.partner + Medusa customer
  - GDPR compliance — opt-in tracking explicit

CE AM ÎNCERCAT: Nimic. Re-eval after operational data.

CONSTRANGERI:
  - Mass mailing Odoo necesită website re-install (dependency cascade)
  - SaaS extern păstrează Odoo curat (preferred per ADR 0003)
  - Cost: Mailchimp €13/mo for 500 contacts vs Postmark $15/mo unlimited transactional
```

### Plan execuție (Q1 2027)

```
1. Pull Odoo customer data: count B2B + segments (mărimi comenzi, freq)
2. WebSearch "Odoo mass_mailing vs Mailchimp B2B 2027 comparison"
3. /compare Odoo native (with website re-install) vs Resend campaigns vs Mailchimp
4. Decizie: dacă rămânem extern, R-004 closed cu "no action"
   Dacă mergem Odoo native, ADR 0004 cu plan re-install controlled (subset modules)
```

---

## R-005 — Custom QWeb pentru afișare doar serie+număr pe PDF (paff_invoice_serial)

**Status:** scoped, blocking pentru lansare facturi B2B (UX clienți)
**Priority:** medium (cosmetic, dar relevant la primii clienți)
**Trigger:** după ETAPA 2 (sequence config aplicat 2026-05-07)

### Context

Cerința user: factura tipărită PDF arată doar `PAFF00001`, dar intern Odoo numele e `FAC/PAFF00001` (cu prefix tip document). Nu există feature out-of-the-box — Odoo afișează `account.move.name` integral pe PDF.

### Plan execuție

```
1. Creez addon paff_invoice_serial cu manifest 19.0.1.0.0
2. Models: NU adaug field nou — folosesc compute pe regex split din name:
   def _compute_paff_doc_serial(self):
       for move in self:
           m = re.match(r'^FAC/(PAFF\d+)$', move.name or '')
           move.paff_doc_serial = m.group(1) if m else move.name
3. Override report template:
   <template id="report_invoice_document_paff" inherit_id="account.report_invoice_document">
       <xpath expr="//span[@t-field='o.name']" position="replace">
           <span t-field="o.paff_doc_serial"/>
       </xpath>
   </template>
4. Same pattern pentru email template invoice_send
5. Tests: posted invoice cu name='FAC/PAFF12346' → PDF arată 'PAFF12346'
```

### Constrângeri

- DEPENDS R-002 — Configuration Centralization (poate paff_doc_serial pe field config)
- Compatibilitate l10n_ro_account_report_invoice (deja instalat) — verifică override conflict

---

## R-006 — Sequences DVZ + CHT + STO + alte tipuri document

**Status:** scoped
**Priority:** medium (depinde de când lansăm primele oferte/chitanțe)

### Context

User a definit pattern multi-prefix:
- `FAC/PAFF<NNNNN>` — factură (out_invoice) ✅ aplicat 2026-05-07
- `DVZ/PAFF<NNNNN>` — deviz / ofertă (sale.order) — TODO
- `CHT/PAFF<NNNNN>` — chitanță (account.payment, type='inbound') — TODO
- `STO/PAFF<NNNNN>` — storno / ramburs (out_refund) — TODO
- Alte tipuri posibile: BON (bon consum), AVZ (aviz expediție), NIR (notă recepție)

### Plan execuție

```
1. sale.order journal — sequence_override_regex DVZ/PAFF\d{5}
2. account.payment — sequence per type (inbound=CHT, outbound=PLT)
3. out_refund — separate journal SALES_REFUND code STO, regex STO/PAFF\d{5}
4. ir.sequence pentru BON, AVZ, NIR (stock pickings)
5. Decision: număr separat per prefix, SAU global counter? (User: per prefix probabil)
```

### Decizii deschise

- Storno preia număr nou (STO/PAFF12347) sau referențiază factura originală (FAC/PAFF12346 → STO/PAFF12346)?
- Documente intracom (auto-factură intracom) — alt prefix?

---

## R-008 — SAF-T D406 export evaluation (third-party module sau custom)

**Status:** scoped, blocking pentru obligație fiscală anuală
**Priority:** HIGH (D406 mandatory anual din 2022 pentru toate companiile RO)
**Trigger:** decembrie 2026 (prima D406 PAFF în Odoo va fi pentru anul 2026)

### Context

PAFF e obligată legal să depună D406 SAF-T (Standard Audit File for Tax) anual până 31 ianuarie pentru anul precedent. Format XML strict OECD + extensii ANAF. L10n_ro Community + OCA NU oferă această capability.

### Alternative considerate

```
A. l10n_ro_saft third-party (Forest&Bytes / Forest IT — €€€ commercial)
   - Pro: maintained, ready-to-use, suport tehnic
   - Contra: cost recurent, dependent vendor

B. DUKIntegrator (tool Java desktop ANAF official, GRATIS)
   - Pro: emisă de ANAF, garantat compliant
   - Contra: extract manual din Odoo Excel → import în DUKIntegrator → review → upload
   - Effort: ~3-4h pe an pentru o singură companie

C. paff_saft_d406 custom addon (50-100h development)
   - Pro: integrare nativă Odoo, control total
   - Contra: development effort + mentenanță anuală (ANAF schimbă schema XML)

D. OCA l10n_ro_saft (dacă apare în 2026 — current: NU există)
   - Watch: github.com/OCA/l10n-romania PRs pentru saft
```

### Plan execuție (Q4 2026)

```
1. Verifică status OCA — există PR pentru l10n_ro_saft?
2. Eval Forest&Bytes pricing (request quote pentru SRL B2B)
3. Test DUKIntegrator pe anul 2026 cu dataset complet PAFF
4. Decide based on:
   - Volum facturi (dacă < 1000/an → DUKIntegrator OK)
   - Buget (dacă există > €500/an → third-party)
   - Strategie long-term (multi-company viitor → custom worth)
```

### Constrângeri

- ANAF schimbă schema XML SAF-T anual (versionare D406)
- Tax codes Odoo trebuie mapped EXACT pe ANAF tax codes
- Stock movements TREBUIE incluse (transferuri intern + adjustments)

---

## R-007 — paff_bnr_currency addon (BNR sync zilnic)

**Status:** scoped, deferred până la prima factură EUR/USD
**Priority:** low (PAFF emite RAR factură valută)

### Context

User confirmat 2026-05-07: PAFF emite "foarte rar in euro". Custom addon e overkill ACUM, dar inevitable când apare nevoie.

### Plan execuție

```
1. Manifest 19.0.1.0.0, depends ['base', 'l10n_ro_config']
2. ir.cron @ daily 12:00 RO time
3. Fetch https://www.bnr.ro/nbrfxrates.xml (XML public, no auth)
4. Parse XML cu lxml, extract currency code + rate
5. Update res.currency.rate cu name=date, rate=value, currency_id=match
6. Audit: post mail.message pe res.company cu rezumat update
7. Error handling: timeout 30s, fallback la curs anterior dacă XML lipsa
8. Tests: mock BNR XML response, verify rate update
```

### Alternative considerate

- A. OCA `currency_rate_update` + `currency_rate_update_RO_BNR` — submodule extra, scalabil
- B. Custom paff_bnr_currency (50 LOC) — minimal, controlăm
- C. Bash cron extern + curl + psql — out-of-band, NO audit Odoo

User a ales B (custom addon mai târziu). Trigger: prima factură EUR/USD reală în paff_prod.

### Constrângeri

- BNR publică curs Luni-Vineri, NU weekenduri/sărbători legale → cron daily rulat dar update doar dacă XML are data zilei curente
- Rate de "azi" e folosit pentru facturi de "mâine" (consistency T-1)
- Câteva monede minore (HUF, JPY, etc.) BNR le publică doar săptămânal — handle absence

---

## R-009 — `mis_builder` deferred until OCA 19.0 port

**Status:** scoped, deferred (verified 2026-05-07: NO 19.0 branch în `OCA/mis-builder`)
**Priority:** medium (replacement available)
**Trigger pentru reluare:** monthly check `OCA/mis-builder` branches; install când 19.0 disponibil

### Context

Plan v2 Phase 2 Batch B intenționa install `mis_builder` + `mis_builder_cash_flow` (custom P&L/Balance Sheet/Cash Flow cu formule configurabile). Verificare 2026-05-07: branch 19.0 NU există în `OCA/mis-builder` (doar 10/16/17/18 active).

### Replacement applied

Installed **`account_financial_report`** din `OCA/account-financial-reporting/19.0` (alt module în acelaşi repo, NU custom formule dar built-in P&L + Balance + Aging + General Ledger). Acoperă 80% din use case-urile pentru cabinet contabilitate.

Trade-off: `mis_builder` permite formule custom (KPI-uri specifice carton, marjă pe categorie). `account_financial_report` e standard accounting reports. Fine pentru launch + 6 luni.

---

## R-010 — `web_widget_color` alternative (native Odoo tags)

**Status:** closed (not needed)
**Priority:** low

### Context

Plan v2 T3 menționa `web_widget_color` pentru color tags pe partneri. Verificare 2026-05-07: NU în `OCA/web/19.0`.

### Resolution

Native Odoo `res.partner.category_ids` (Tags) cu `color` field (10 built-in colors) acoperă use case. NU mai e nevoie de OCA module separate.

---

## Convenție backlog

- **Format ID**: `R-NNN` cu padding 3 cifre (R-001, R-002, ...)
- **Priority**: HIGH (blocking) / medium / low
- **Status**: scoped → executed → consumed-in-plan → implemented
- **Estimated research effort**: minute pe baza numărului de calls

### Adăugare topic nou

1. Editează acest fișier
2. Adaugă secțiune nouă cu `R-NNN` succesiv
3. Completează scope-ul în format complet (PROBLEMA/STACK/CE AM INCERCAT/CONSTRANGERI/CUTOFF)
4. Listează plan execuție (3-10 calls)
5. Notează decizii probabil deschise

### Execuție efectivă

Când e timpul să rulezi research-ul pentru un topic:

```bash
# Copiază scope-ul din backlog → seed pentru /cauta
# Output ajunge la ~/.claude/data/research/<slug>.md
# Apoi /plan-session sau /paff-plan cu raportul ca input
```
