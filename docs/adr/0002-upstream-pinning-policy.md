# ADR 0002 — Upstream Pinning Policy + Update Alerting

**Status:** Accepted
**Date:** 2026-05-06
**Deciders:** poparcosmin@gmail.com

## Context

Odoo Community publică update-uri continuu pe Docker Hub:
- `odoo:latest` — mutabil, primește orice
- `odoo:19` — major track, primește toate patches în 19.x
- `odoo:19.0` — minor track, primește toate patches în 19.0-* (mutabil)
- `odoo:19.0-20260501` — calendar version, **aparent** imutabil
- `odoo:19.0-20260501@sha256:abc...` — content-addressed, **garantat** imutabil

Folosirea `:latest` sau `:19` în production = `docker compose pull` poate aduce orice schimbare silent. Pentru ERP cu date fiscale, e inacceptabil:
- Schema migration neprevăzut → DB corupt
- Comportament schimbat în `account.move` → facturi greșite la client
- Security regression → vector de atac

Dar pinning fără mecanism de update = security debt acumulat (CVE-uri ne-aplicate).

## Decizia

**Combo: pinning strict + alerting automat + update controlat.**

### 1. Pinning în `docker/Dockerfile`

```dockerfile
ARG ODOO_VERSION=19.0-YYYYMMDD       # calendar version explicit (liniuță, nu punct)
ARG ODOO_DIGEST=sha256:abc1234...    # content-addressed, imutabil

FROM odoo:${ODOO_VERSION}@${ODOO_DIGEST}
```

**Niveluri rejected:**
- ❌ `odoo:latest` — mutabil total
- ❌ `odoo:19` — major track, primește patches silent
- ❌ `odoo:19.0` — minor track, idem
- ⚠ `odoo:19.0-20260501` (fără digest) — protejat parțial, dar tag-urile pot fi re-publicate
- ✅ `odoo:19.0-20260501@sha256:...` — garantat imutabil

### 2. Alerting prin Renovate Bot

`renovate.json` la rădăcină configurat cu:
- `pinDigests: true` — propune update-uri cu digest fresh
- `vulnerabilityAlerts.enabled: true` — alert imediat pentru CVE
- `packageRules` pentru Odoo: grup separat, manual review obligatoriu, `minimumReleaseAge: 3 days` (evită release-uri broken)
- PR template cu checklist obligatoriu (smoke test, changelog review, backup pre-merge)

### 3. Cron monitor backup (în caz Renovate down)

`scripts/check-odoo-update.sh` rulat zilnic prin cron-monitor PAFF la 07:00 RO time:
- Query Docker Hub `/v2/repositories/library/odoo/tags`
- Compare cu `ARG ODOO_VERSION` din `docker/Dockerfile`
- Classifier severity (3 niveluri: patch / minor / security CVE)
- Output → Telegram via skill `tg`
- Pentru severity ≥ 20 (minor sau security): auto-create GitHub issue cu label `upstream-update`

### 4. Update flow controlat

```bash
# Recomandat: prin script (smoke test included)
scripts/update-odoo.sh --target 19.0-20260601 --dry-run
scripts/update-odoo.sh --target 19.0-20260601

# Sau prin Renovate PR review + merge
```

NU se modifică manual `Dockerfile` cu version+digest fără rulare smoke test.

## Severity Levels

| Nivel | Trigger | Action | SLA |
|-------|---------|--------|-----|
| **30 — Security CVE** | `CVE-` în changelog, security advisory | Telegram urgent + GitHub issue + label `urgent` | < 24h staging, < 72h prod |
| **20 — Minor (business logic)** | `fix` + cuvinte fiscale (`invoice`, `tax`, `VAT`, `ANAF`, `account.move`, etc.) | Telegram normal + GitHub issue | < 7 zile |
| **10 — Patch (low severity)** | Restul (refactor, doc, fixes în module ne-folosite) | Aggregated weekly digest | < 30 zile |

**Severity classifier-ul** e în `scripts/check-odoo-update.sh`, funcția `classify_update()`. Definit prin keywords (TODO user-defined la primul update real — vezi comentariul din script).

## Reproductibilitate

Pinning-ul cu digest garantează că:
- Build-ul aceluiași `Dockerfile` produce IDENTIC același image content (modulo build cache)
- Restore-ul unui backup pe alt host folosește EXACT același Odoo runtime
- Investigation cu digest-ul → poți pull versiunea EXACTĂ care rula când a apărut bug-ul

## Consequences

### Pozitive
- Production stability garantată — niciun "auto-update silent"
- Audit trail: fiecare bump de versiune e PR cu changelog + smoke test logs
- Compliance fiscal RO (ANAF poate cere reproductibilitate până la 5 ani)
- CVE-uri nu se acumulează — Renovate alertează zilnic

### Negative
- Overhead operațional: review săptămânal de PR-uri Renovate
- Smoke test cere maintenance — TODO conditions (definite de user, vezi `scripts/update-odoo.sh`)
- Renovate Bot e dependență externă (GitHub App)

### Mitigations
- Cron monitor `check-odoo-update.sh` ca fallback dacă Renovate fail
- Smoke test minim (health endpoint) e suficient ca baseline; user adaugă tests funcționale incremental

## References

- Docker docs: [Image versioning best practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- Renovate docs: [Docker datasource](https://docs.renovatebot.com/modules/datasource/docker/)
- Supply chain attacks: SLSA framework, Sigstore
- ADR 0001 — Three-Layer Isolation (complementary)
