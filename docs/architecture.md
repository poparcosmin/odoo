# PAFF Odoo — Architecture Overview

## Three-Layer Isolation

Vezi [ADR 0001](adr/0001-three-layer-isolation.md) pentru detalii complete.

```
┌──────────────────────────────────────────────────────────────┐
│  LAYER 3: src/addons/  — WRITE FREELY                        │
├──────────────────────────────────────────────────────────────┤
│  LAYER 2: patches/    — DOCUMENTED EXCEPTIONS ONLY           │
├──────────────────────────────────────────────────────────────┤
│  LAYER 1: src/odoo/   — READ-ONLY (enforced by hook)         │
└──────────────────────────────────────────────────────────────┘
```

## Sistem complet — diagrama

```
                                   Internet
                                       │
                                  ┌────▼────┐
                                  │  Nginx  │  HTTPS, HSTS, CSP
                                  │  (VPS)  │  managed extern, gestionat per-domeniu
                                  └────┬────┘
                                       │
                       ┌───────────────┼────────────────┐
                       │               │                │
                  ┌────▼────┐    ┌─────▼─────┐    ┌─────▼─────┐
                  │paff.ro  │    │erp.paff.ro│    │admin.paff │
                  │(Medusa  │    │  (Odoo)   │    │   .ro     │
                  │frontend)│    │ this repo │    │(dashboard)│
                  └────┬────┘    └─────┬─────┘    └─────┬─────┘
                       │               │                │
                       │   JSON-RPC    │                │
                       └───────────────┼────────────────┘
                                       │
                                  ┌────▼────────────┐
                                  │ PostgreSQL 17   │  Per-stack DB:
                                  │ paff-erp-postgres│  • paff_prod (acest repo)
                                  └────┬────────────┘  • paff_test
                                       │              (Medusa folosește alt PG)
                                       │
                              ┌────────┴────────┐
                              │   Filestore     │
                              │ (attachments,   │
                              │  PDF, imagini)  │
                              └─────────────────┘
```

**Production deploy**: nginx-ul VPS (Ubuntu 24, OVH) face SSL termination + reverse proxy la `127.0.0.1:8310`. Odoo + Postgres rulează în Docker Compose (`docker-compose.prod.yml`) izolat. SSL prin Let's Encrypt via certbot (auto-renewal).

Detalii: [`docs/runbooks/deploy-vps.md`](runbooks/deploy-vps.md), [`docs/deploy/`](deploy/).

## Integrare Medusa ↔ Odoo

**Tip:** categoria 3 "Remote but owned" din [architecture-principles.md](file:///home/cosmin/.claude/rules/architecture-principles.md).

**Pattern:** Ports & Adapters
- Port (interface în Medusa): `OdooClient` — definește metodele apelate
- Production adapter: `OdooHttpClient` — face JSON-RPC către `erp.paff.ro`
- Test adapter: `OdooInMemoryClient` — fixturi pentru tests Medusa

**Sync direction:**

| Action | From | To | Mechanism |
|--------|------|------|-----------|
| Order placed | Medusa | Odoo | Webhook → JSON-RPC `account.move.create` |
| Inventory level changed | Odoo | Medusa | Cron poll Odoo → Medusa Stock service |
| Customer fiscal validation | Medusa | Odoo | JSON-RPC `res.partner.create` cu CIF ANAF-validated |
| Invoice PDF | Odoo | Medusa | URL signed, render on-demand |
| Product master data | Odoo | Medusa | Cron poll, idempotent upsert |

**Eventual consistency:** sync-ul nu e real-time. SLA-uri:
- Order → Invoice: < 5 min
- Inventory: < 15 min
- Customer fiscal: real-time on demand

## Backup Architecture

```
┌────────────────────────────┐
│  data/live/                │  PostgreSQL data dir
│   └── PG_VERSION_19/       │  (volume Docker bind-mount)
└────────────┬───────────────┘
             │ pg_dump --format=custom
             ▼
┌────────────────────────────┐
│  data/backup/              │
│   ├── daily/   (7 keep)    │  GFS retention
│   ├── weekly/  (4 keep)    │
│   └── monthly/ (60 keep)   │  5 ani (legal RO)
└────────────────────────────┘

┌────────────────────────────┐
│  data/filestore/           │  Attachments (PDF, imagini)
│   └── paff_prod/           │  ⚠ NU sunt în PG, backup separat OBLIGATORIU
│       └── ab/abcd1234...   │
└────────────┬───────────────┘
             │ tar -czf
             ▼
┌────────────────────────────┐
│  data/backup/<type>/       │  Filestore inclus în backup
│   └── paff_prod-YYYYMMDD/  │  alături de db.dump
│       ├── db.dump          │
│       ├── filestore.tar.gz │
│       ├── MANIFEST         │
│       └── checksums.sha256 │
└────────────────────────────┘
```

## Upstream Update Flow

```
Renovate Bot
   │ daily check Docker Hub
   ▼
[New version detected]
   │
   ├─→ vulnerabilityAlerts? ─yes→ urgent label, schedule "any time"
   │
   └─→ regular schedule: monday 06:00 RO
       │
       ▼
   [Open PR] cu changelog + checklist
       │
       ▼
   ┌── Reviewer ──┐
   │ - Run dry-run smoke test
   │ - Backup paff_prod
   │ - Sunset patches/ check
   │ - Merge if green
   └────┬─────────┘
        │
        ▼
   git pull → docker compose build
        │
        ▼
   Production deployed
```

## Reference docs

- [ADR 0001 — Three-Layer Isolation](adr/0001-three-layer-isolation.md)
- [ADR 0002 — Upstream Pinning Policy](adr/0002-upstream-pinning-policy.md)
- [Runbook — Upgrade](runbooks/upgrade.md)
- [Runbook — Incident](runbooks/incident.md)
- [Patches workflow](../patches/README.md)
- [Patch template](templates/patch.md)
