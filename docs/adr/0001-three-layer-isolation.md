# ADR 0001 — Three-Layer Isolation pentru Odoo Customizations

**Status:** Accepted
**Date:** 2026-05-06
**Deciders:** poparcosmin@gmail.com

## Context

Acest repo customizează Odoo 19 pentru deployment pe `erp.paff.ro` și integrare cu Medusa la `paff.ro`. Există o tensiune între:

1. **Stabilitate upstream** — vrem `git pull` curat din `odoo/odoo` fără merge conflicts
2. **Customizare PAFF** — TVA RO, e-Factura SPV, integrare Odoo↔Medusa, business rules specifice
3. **Hotfix capability** — uneori upstream are bug critic și nu putem aștepta release oficial

Soluții naive eșuează:
- "Modifică direct în Odoo source" → pierdere garantată la `git pull`
- "Numai addon-uri custom" → unele bug-uri sunt în startup/core, ne-overridable din addon
- "Fork complet cu rebase periodic" → maintenance overhead enorm, conflicts la fiecare release

## Decizia

Adoptăm **Three-Layer Isolation**: trei nivele cu reguli clare, hook-uri structurale care enforce boundaries.

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

### Layer 1 — `src/odoo/`

**Regulă:** READ-ONLY. Niciun fișier nu se modifică niciodată.

**Scop:**
- IDE indexing & autocomplete pentru `_inherit("res.partner")`
- `grep -r "_compute_amount" src/odoo/` rapid
- Debugging cu sources locale când debugger atașează la container
- Citit pattern-uri Odoo (cum se face wizard, controller, etc.)

**NU e folosit ca runtime.** Container-ul rulează din imaginea oficială Docker Hub `odoo:19.0-YYYYMMDD@sha256:...` (vezi ADR 0002).

**Update flow:**
```bash
cd src/odoo
git pull origin 19.0   # mereu clean, n-am modificat nimic
```

**Enforcement:**
- Hook Claude Code `src-odoo-readonly-guard.sh` (PreToolUse:Edit|Write) blochează scrierea
- `.gitattributes` cu `linguist-vendored=true` semnalizează în GitHub
- `.gitignore` la rădăcina parent repo include `src/odoo/`

### Layer 2 — `patches/`

**Regulă:** EXCEPȚII documentate. Default = NU folosi.

**Când folosim:**
- Bug în startup (`odoo-bin` init, înainte ca addon-urile să se încarce)
- Security patch critic înainte de release upstream
- Schimbare în `odoo.tools.config` sau alt loc unde inheritance nu funcționează

**Convenție:**
```
patches/NNNN-titlu-scurt.patch
patches/NNNN-titlu-scurt.md      # OBLIGATORIU: justificare + sunset criteria
```

**Aplicare:** `docker/entrypoint.sh` aplică patches la container start, în ordine, cu dry-run check.

**Sunset:** fiecare patch are condiție explicită de ștergere (upstream PR merged, addon înlocuitor finalizat, etc.). Review lunar.

**Anti-pattern interzis:** "hotfix temporar" fără sunset criteria. Toate patch-urile sunt temporare prin definiție.

### Layer 3 — `src/addons/`

**Regulă:** WRITE FREELY. Aici trăiește 99% din customizarea PAFF.

**Sub-categorii:**

1. **`paff_*`** — addon-uri custom PAFF (paff_contact_intelligence, paff_inventar_carton, etc.)
2. **`l10n_ro_*`** — OCA modules pentru România (NU modifica, sunt upstream)
3. **`extensions/`** — addon-uri care fac monkey-patching la runtime pentru cazuri unde inheritance ORM nu ajunge

**Pattern preferat:** `_inherit` ORM + `<xpath>` views. 99% din nevoi se rezolvă aici.

## Backup-ul ține cont de toate trei layerele

Backup-ul Odoo trebuie să capteze:
1. **PostgreSQL** (state-ul DB) → `data/live/`
2. **Filestore** (attachments PDF/imagini) → `data/filestore/`
3. **Patches active** (Layer 2) → `patches/` (e în git)
4. **Custom addons** (Layer 3) → `src/addons/` (e în git)

`scripts/backup-db.sh` face 1+2. Layerele 3+4 sunt în git, deci backup-ul e VCS-based.

## Consequences

### Pozitive
- `git pull` în `src/odoo/` mereu curat — zero merge conflicts
- Audit trail clar: orice modificare e fie în `patches/` (cu doc), fie în `src/addons/` (cu commit)
- Onboarding nou dev: 3 reguli simple de înțeles
- Update Odoo upstream e operațional, nu apocaliptic

### Negative
- Layer 2 (patches) cere disciplină — risc de "patches-graveyard" dacă sunset nu e enforced
- Hook Claude Code adaugă o dependință la workflow (mitigat: hook e simplu, no false positives)
- Dezvoltatorii pot fi tentați să "hot-edit src/odoo/" în debugging — hook-ul îi oprește

### Neutral
- ~600 MB stocare locală pentru `src/odoo/` (cost neglijabil)
- Necesită un al doilea repo `paff-odoo-addons` SAU layout-ul actual cu `src/addons/` în acest repo (decizie deschisă — vezi întrebarea 2 din primul mesaj)

## References

- John Ousterhout, *A Philosophy of Software Design* — modules deep, information hiding
- Debian packaging conventions — quilt patches workflow
- Kubernetes kustomize — overlay pattern peste base manifests
- ADR 0002 — Upstream Pinning Policy (complementary)
