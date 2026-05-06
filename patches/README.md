# patches/ — Layer 2 din Three-Layer Isolation

> **Înainte de a adăuga un patch aici, întreabă-te:** poate fi rezolvat printr-un addon `_inherit` în `src/addons/`? În 99% din cazuri DA. Patches-urile sunt EXCEPȚIE, nu regulă.

## Când folosim patches?

Doar pentru cazuri unde mecanismele native Odoo (inheritance ORM, view xpath, monkey-patching la runtime) NU pot acoperi nevoia:

- Bug în startup (`odoo-bin` init-time, înainte ca addon-urile să se încarce)
- Security patch critic înainte de release upstream
- Schimbare în comportament fundamental (ex: `odoo.tools.config` parsing)

Toate celelalte cazuri → addon `paff_*` cu `_inherit`.

## Convenție de nume

```
NNNN-titlu-scurt.patch    # diff-ul efectiv (output din git format-patch)
NNNN-titlu-scurt.md       # justificarea + sunset criteria
```

`NNNN` = 4 cifre, ordine cronologică (0001, 0002, ...).

## Workflow adăugare patch

1. Reproducere bug în staging container (NU production)
2. Modifică sources în staging container, valid fix
3. Generează patch:
   ```bash
   docker exec paff-odoo-staging \
     diff -u /usr/lib/python3/dist-packages/odoo/<file>.orig \
             /usr/lib/python3/dist-packages/odoo/<file> \
     > patches/NNNN-titlu.patch
   ```
4. Completează `patches/NNNN-titlu.md` din template-ul `docs/templates/patch.md`
5. Test cu `--dry-run` în entrypoint:
   ```bash
   docker compose build odoo && docker compose up odoo
   ```
6. Commit cu mesaj `patch: NNNN <titlu> (sunset: <condition>)`

## Workflow ștergere patch (sunset)

Când condiția de sunset e îndeplinită (vezi `.md` aferent):

1. Verifică că upstream / addon înlocuitor rezolvă cazul
2. Șterge perechea `NNNN-titlu.patch` + `NNNN-titlu.md`
3. Șterge marker-ul aplicat: `docker exec paff-odoo rm /var/lib/odoo/.patches-applied`
4. Rebuild image: `docker compose build odoo`
5. Commit cu mesaj `patch: remove NNNN <titlu> (sunset triggered: <reason>)`

## Audit periodic

Lunar, review fiecare patch activ:
- Sunset condition încă neîndeplinită? Dacă DA → notă în patch `.md`
- Sunset condition îndeplinită? Procedează la ștergere
- Patch-ul mai e necesar? (poate addon-ul `paff_X` rezolvă acum)

## Anti-patterns INTERZISE

- ❌ Patch fără `.md` de justificare
- ❌ Patch fără sunset criteria explicit
- ❌ "Hotfix temporar" care rămâne 6 luni
- ❌ Modificare directă în `src/odoo/` în loc de patch (hook-ul read-only blochează)
- ❌ Patch care poate fi înlocuit cu `_inherit` (lazy escape)
