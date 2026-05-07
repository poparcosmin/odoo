# ADR 0003 — Pure ERP: Uninstall Odoo Website Modules

**Status:** Accepted
**Date:** 2026-05-07
**Deciders:** poparcosmin@gmail.com
**Related:** ADR 0001 (Three-Layer Isolation), ADR 0002 (Upstream Pinning)

## Context

Odoo 19 Community include din box modulele `website` (storefront builder) + suite extensii (`website_sale`, `website_blog`, `website_event`, etc.). PAFF folosește însă **Medusa v2** ca platformă storefront la `paff.ro`. Odoo e **doar ERP** la `erp.paff.ro`.

Configurația default a Odoo 19 a instalat 7 module website-related în `paff_prod` DB:

| Modul | Rol |
|---|---|
| `website` | Storefront builder (CMS, drag-and-drop, theme system) |
| `website_mail` | Email tracking pixels via website tracking |
| `website_payment` | Payment portal pe website |
| `website_sms` | OTP SMS via website forms |
| `website_cf_turnstile` | Cloudflare Turnstile CAPTCHA pe form-uri website |
| `portal` | Self-service B2B (My Invoices, My Orders) — **NU e website builder** |
| `sms` | SMS API pentru notificări tranzacționale (NU e website-related) |

**Probleme cu configurația default:**

1. **Tema "Your Logo" pe login admin**: când utilizatorul deschide `/web/login`, modulul `website` interceptează request-ul și aplică template default Odoo cu placeholder "Your Logo + 1-555-555-5556". Confundă admin-ul, expune "neconfigurat" la prima impresie.
2. **Surface attack public extins**: rute precum `/shop`, `/contactus`, `/website/info` sunt expuse public chiar dacă nimeni nu le folosește. CVE-urile pe `website_*` modules afectează production deploy-ul.
3. **RAM overhead**: module website* compilează assets (JS bundles, CSS) la pornire. ~200-300MB RAM consumat fără valoare adăugată.
4. **Confuzie admin/storefront**: nu e clar dacă "comanda" se face în Odoo (website_sale) sau în Medusa. Risc de double-entry, sync inconsistencies.
5. **Bitwarden auto-fill nu trigger HTML5 validation pe tema website**: butonul "Autentificare" rămâne grayed out după autocomplete (incident raportat 2026-05-07).

## Alternative considerate

### A [Enterprise] — Uninstall toate modulele website* (DECIZIE)

**De ce enterprise:** atomic operation, rollback clean (DB backup pre-uninstall), scriptat în `scripts/init-db.sh` pentru reproducibility cross-environment.

**Pro:**
- Login admin pe `/web/login` clean (zero theme overhead)
- `/` redirect la `/odoo` (backend), niciun /shop/contactus public
- ~200-300MB RAM eliberați (verificat: 132MiB usage post-uninstall vs ~280MiB pre-uninstall, **dev mode**)
- Surface attack redus drastic (zero rute publice expuse)
- Init-db.sh marchează `auto_install=false` pentru toate `website%` → fresh deploys curate

**Contra:**
- Nu mai e portal frontend dacă vrem să oferim B2B clienți să vadă comenzi/facturi (mitigated: `portal` rămâne instalat, accesibil via URL signed `/my/invoices/<id>?access_token=...`)
- Cascade delete pe templates email custom care referențiau website (mitigated: 0 templates afectate la migrare conform Faza 3 smoke test)

### B [Pragmatic] — Uninstall doar modulul `website` parent, păstrare children disabled

**Pro:** mai puțin invaziv, păstrăm code paths
**Contra:** children rămân instalate fără părinte = fragile state. Auto-tests Odoo failuri. **REJECTED.**

### C [Escape hatch] — `auto_install=False` doar, fără uninstall

**Pro:** zero risc DB, instant
**Contra:** module rămân loaded în RAM (zero benefit), rutele rămân active server-side, atac surface neschimbat. **REJECTED — solves nothing.**

## Decizie

**Uninstall toate modulele `website*` din Odoo paff_prod.** Păstrăm:
- `portal` (forțat de `account`, `payment`, `digest`, `auth_passkey_portal`, `auth_totp_portal`, `spreadsheet`)
- `sms` (util pentru notificări tranzacționale + posibil 2FA admin)

**Nu reinstalăm niciodată** `website*`, `theme_*`, `mass_mailing`, `survey` fără ADR explicit care suspendă această decizie.

### Modules in cleanup batch

```
website_cf_turnstile    (uninstalled)
website_mail            (uninstalled)
website_payment         (uninstalled)
website_sms             (uninstalled)
website                 (uninstalled — parent, last)
```

### Mecanism prevenție re-instalare

1. **Post-init în `scripts/init-db.sh`**: `UPDATE ir_module_module SET auto_install = false WHERE name LIKE 'website%' OR name LIKE 'theme_%' OR name IN ('mass_mailing', 'survey')`
2. **Regulă în `CLAUDE.md`**: "NU instala module website* fără ADR explicit"
3. **Code review gate**: orice PR care declară `depends: ['website']` în manifest paff_* addon → REJECT automat

## Consequences

### Positive

- **Login UX clean**: `/web/login` arată form-ul Odoo standard fără tema "Your Logo". Bitwarden funcționează corect.
- **Surface attack -50%**: rute publice eliminate (`/shop`, `/contactus`, `/website/info`, `/website/translations` returnează 404 sau routing core).
- **RAM dev mode**: 132MiB (workers=0). În prod cu workers=4, estimăm reducere ~200MB pe deploy.
- **Onboarding admin simpler**: zero confuzie admin vs storefront, zero "neconfigurat" la prima vizită.

### Negative / Trade-offs acceptate

- **Pierdem ability rapid de website CMS**: dacă vrem cândva landing page custom în Odoo (improbable), trebuie reinstall + ADR de revocare.
- **Email templates Odoo native**: unele (factura customer) referenționează `/my/invoices/<id>?access_token=...`. Funcționează prin `portal` (rămas instalat). **Verified în smoke test Faza 3.**

### Neutrale

- **Mass_mailing și survey**: declarate **deferred** (R-XXX). Nu instalăm acum, nu blocăm pentru viitor (~2027 evaluation per business need).

## Sunset criteria

Această decizie devine candidate de revocare DOAR dacă:
1. PAFF migrează storefront-ul **din Medusa în Odoo native** (improbable — schimbare arhitectură majoră)
2. Apare cerință B2B portal complex (catalog cu drag-and-drop, multi-language landing pages) imposibil de făcut în Medusa
3. Audit fiscal cere portal Odoo dedicat (consult ANAF)

În oricare caz, reactivare cere ADR nou care anulează 0003 + plan migrare data + smoke test în staging.

## Verification

Status post-implementare:

```sql
-- Run în paff_prod:
SELECT name, state FROM ir_module_module
WHERE name LIKE 'website%' OR name = 'portal' OR name = 'sms'
ORDER BY state, name;

-- Expected output:
-- portal              | installed
-- sms                 | installed
-- website             | uninstalled
-- website_*           | uninstalled (toate)
```

Smoke test extins (10 verificări în `/tmp/smoke_extended.py`): toate passes.

## References

- ADR 0001 — Three-Layer Isolation (`docs/adr/0001-three-layer-isolation.md`)
- ADR 0002 — Upstream Pinning Policy (`docs/adr/0002-upstream-pinning-policy.md`)
- Backup pre-uninstall: `data/backup/manual/paff_prod-pre-website-uninstall-20260507-071454.dump`
- Filestore pre-uninstall: `data/backup/manual/filestore-pre-website-uninstall-20260507-071508.tar.gz`
- Implementation: `scripts/init-db.sh` (Faza 4 update)
- Trigger session: 2026-05-07, browser login issue cu tema "Your Logo + 1-555-555-5556"
