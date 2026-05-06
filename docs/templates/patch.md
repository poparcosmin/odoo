# Patch NNNN — <titlu scurt>

**Date created:** YYYY-MM-DD
**Author:** <nume>
**Affects:** `<path/to/file/in/odoo/source>`
**Odoo version pinned:** `<output din docker inspect ... RepoDigests>`

## Problema

<Descriere concretă a bug-ului sau lipsei. Include:>
- Ce comportament se observă (cu logs sau steps to reproduce)
- Ce comportament e așteptat
- Impact business (cine e afectat, frecvență, severitate)

## De ce NU printr-un addon `_inherit`?

<OBLIGATORIU justificat. Exemple valide:>
- Bug-ul e în `odoo-bin` startup, înainte ca addon-urile să se încarce
- Codul afectat nu expune hook de inheritance (`@api.model_create_multi` lipsă)
- Schimbarea e în `odoo.tools` care nu e ORM model
- Security patch unde delay-ul de release upstream e inacceptabil

<DACĂ poți rezolva prin addon → ȘTERGE acest patch și fă addon. NU continua.>

## Soluția (diff summary)

<Descriere de înalt nivel a patch-ului. Diff-ul detaliat e în `.patch`.>

```diff
# Conceptual diff (NU copy-paste din .patch — doar ideea)
- old behavior
+ new behavior
```

## Alternative considerate

<Cel puțin 2 alternative + de ce nu sunt fezabile:>
1. **Addon `paff_X` cu `_inherit`** — nu funcționează pentru că <motiv concret>
2. **Monkey-patching la runtime** — nu funcționează pentru că <motiv concret>
3. **Așteptare upstream fix** — risk acceptat / inacceptat pentru că <motiv>

## Sunset criteria

<OBLIGATORIU concret și verificabil. Exemple:>
- [ ] Upstream PR <link> merged și released în versiunea `19.0-YYYYMMDD` sau superior
- [ ] Addon `paff_X` finalizat și deployed în production (issue #NNN)
- [ ] Migrare la Odoo 20.0 (când)
- [ ] CVE-YYYY-NNNNN closed în security advisory upstream

**Review schedule:** lunar (next: YYYY-MM-DD)

## Upstream tracking

- GitHub issue: <link sau "none filed">
- Pull request submitted: <link sau "none — TODO">
- Mailing list discussion: <link sau "n/a">

## Test coverage

<Cum verifici că patch-ul funcționează după build:>

```bash
# Test concret (pas cu pas)
docker compose up -d odoo
docker exec paff-odoo <comanda care reproduce scenariul>
# Output expected: <ce trebuie să vezi>
```

## Rollback procedure

<Dacă patch-ul cauzează probleme în production:>

```bash
# 1. Comentează linia patch-ului în patches/<numele>.patch
# 2. Șterge marker-ul aplicat
docker exec paff-odoo rm /var/lib/odoo/.patches-applied
# 3. Rebuild
docker compose build odoo && docker compose up -d odoo
```
