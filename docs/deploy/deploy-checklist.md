# First-Time Deploy Checklist

Quick pre-flight + deploy checklist. Detalii complete: `runbooks/deploy-vps.md`.

## Pre-flight

- [ ] DNS `erp.paff.ro` → VPS IP (verifică cu `dig erp.paff.ro`)
- [ ] SSH access la VPS funcțional (`ssh ovh "uname -a"`)
- [ ] Docker + Docker Compose v2 instalate pe VPS
- [ ] Nginx instalat + funcțional (verifică `nginx -t`)
- [ ] certbot instalat (`certbot --version`)
- [ ] `~/.ssh/config` are alias `ovh` setat
- [ ] GitHub repo accesibil prin SSH key (`ssh -T git@github.com` din VPS)

## Deploy

- [ ] Folder layout creat (`~/web/erp.paff.ro/{repo,data/{live,backup,filestore},logs}`)
- [ ] Repo cloned cu `--recurse-submodules`
- [ ] `.env` populat cu secrete reale (run `scripts/generate-secrets.sh --update`)
- [ ] Docker image built (`docker compose ... build odoo`)
- [ ] DB initialized cu `scripts/init-db.sh paff_prod`
- [ ] Nginx config installed + tested (`nginx -t`)
- [ ] SSL cert obtained (`certbot --nginx -d erp.paff.ro`)
- [ ] systemd unit installed + enabled
- [ ] Browser test: `https://erp.paff.ro/web/login` → 200 OK
- [ ] Login admin → schimbă parola IMEDIAT

## Post-deploy

- [ ] Cron backup setat (daily/weekly/monthly)
- [ ] Offsite backup verified (rsync la storage extern)
- [ ] Telegram bot conectat (test alert)
- [ ] Cron monitor `check-odoo-update.sh` setat (zilnic 07:00 RO)
- [ ] Master password rotat (NU folosi default)
- [ ] `/web/database/manager` restricționat IP în nginx (uncomment block in config)
- [ ] Documentat undeva: VPS IP, admin password, backup encryption key (password manager)

## Smoke test funcțional

- [ ] Login admin → 200
- [ ] Settings → Companies → set company name + CIF + adresă
- [ ] Contacts → creare partner test cu CIF "RO12345678" → ANAF lookup OK
- [ ] Settings → Languages → Romanian set as default
- [ ] Currency → RON set as company currency
- [ ] Schimbă timezone user în Europe/Bucharest

## Recovery test (după prima săptămână de uptime)

- [ ] Backup restore pe DB temporar (`paff_test_restore`)
- [ ] Smoke test pe DB restaurat (login, listing partners)
- [ ] Drop DB temporar
- [ ] Document timpul de restore în runbook
