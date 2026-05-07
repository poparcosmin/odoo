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
