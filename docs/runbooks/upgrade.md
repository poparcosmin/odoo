# Runbook — Upgrade Odoo Upstream

## When triggered
- Renovate Bot deschide PR cu `chore(deps): update odoo from X to Y`
- Cron monitor trimite Telegram alert "🚨 SECURITY CVE" sau "⚠️ MINOR"
- Manual: vrei să verifici dacă există versiune nouă

## Pre-flight checklist
- [ ] Production stabil (no active incidents în ultimele 24h)
- [ ] Backup recent făcut (< 24h vechi): `ls -lat data/backup/daily/ | head -3`
- [ ] Staging environment available
- [ ] PAFF Ecommerce monorepo NU e în mijlocul unui release Medusa (cross-system risk)

## Procedure

### 1. Review changelog
```bash
# Din PR Renovate: review release notes
gh pr view <PR_NUMBER>

# SAU manual:
git diff <current_version>...<new_version> --stat
```

Întrebări de pus:
- Schema migration referenced? → DB backup obligatoriu, restore plan ready
- Module noi marked deprecated? → Verifică că PAFF nu le folosește
- Security CVE list? → Verifică dacă afectează expunerea PAFF

### 2. Smoke test în staging
```bash
scripts/update-odoo.sh --target 19.0.YYYYMMDD --dry-run

# Dacă dry-run pass:
scripts/update-odoo.sh --target 19.0.YYYYMMDD
# → script rulează smoke test automat
```

### 3. Sunset patches (Layer 2)
Verifică că patches/ încă sunt necesare:
```bash
for patch in patches/*.md; do
  echo "=== $patch ==="
  grep -A 5 "Sunset criteria" "$patch"
done
```

Pentru fiecare patch cu sunset triggered → șterge perechea `.patch` + `.md`.

### 4. Backup production înainte de merge
```bash
scripts/backup-db.sh paff_prod --type daily
# Verifică în data/backup/daily/<latest>/MANIFEST
```

### 5. Merge & deploy
```bash
gh pr merge <PR_NUMBER> --squash
git pull origin main
docker compose --profile erp up -d --build odoo
docker compose logs -f --tail=100 odoo
```

### 6. Post-deploy validation
- [ ] `/web/health` returnează 200
- [ ] Login admin funcționează
- [ ] Listare facturi → response < 2s
- [ ] Creare partner test cu CIF valid → ANAF lookup OK
- [ ] Sync Medusa → Odoo: ultima comandă apare ca draft invoice
- [ ] Logs Odoo: zero ERROR în primele 5 min după restart

### 7. Rollback (dacă apar probleme)
```bash
# Restore versiunea anterioară din git
git revert <merge_commit>
git push origin main

# Sau rapid: pin version vechi în Dockerfile
# (vezi MANIFEST din ultimul backup)

# Restore DB dacă schema migration a corupt date
scripts/restore-db.sh data/backup/daily/paff_prod-YYYYMMDD-HHMMSS paff_prod

docker compose --profile erp up -d --build odoo
```

## Failure modes documentate

### Container unhealthy after update
- Verifică `docker logs paff-odoo --tail=200`
- Caz frecvent: schema migration failed → restore DB din backup, pin version vechi
- Patches/ break against new version → check `[paff] ✗ Patch ... fails dry-run` în logs

### Smoke test fails dar nu e clar de ce
- Run staging container interactive: `docker run -it --rm paff-odoo:staging bash`
- Verifică manual healthcheck: `curl http://localhost:8069/web/health`
- Compară differences cu container production stabil

### Renovate Bot opens PR but cron monitor doesn't
- Verifică `~/.claude/data/cron-monitor.log`
- Manual run: `scripts/check-odoo-update.sh`
- Verifică Telegram bot token în `.env`
