# Research Backlog — PAFF Odoo

> Topice de cercetat înainte de implementare. Fiecare entry are scope complet
> definit (PROBLEMA / STACK / CE AM INCERCAT / CONSTRANGERI) ready pentru
> `/cauta` execuție directă, fără re-interview.
>
> Workflow: când e timpul să implementezi, copiază scope-ul + rulează `/cauta`
> cu argumentele preserved. Output ajunge in `~/.claude/data/research/<slug>.md`,
> apoi `/plan-session` pentru plan + critique.

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
