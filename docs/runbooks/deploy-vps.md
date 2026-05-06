# Runbook — Deploy PAFF Odoo pe VPS (OVH, Ubuntu 24)

## Presupuneri

- **VPS:** Ubuntu 24, accesibil prin `ssh ovh` (alias preconfigurat în `~/.ssh/config`)
- **Path deployment:** `~/web/erp.paff.ro/` (convenție user)
- **Nginx:** instalat și gestionat extern, deja configurat pentru alte domenii
- **Let's Encrypt:** certbot activ, auto-renewal funcțional
- **Docker + Docker Compose v2:** instalat pe VPS

## Pre-flight (ÎNAINTE de prima deploy)

### 1. Verify SSH + dependencies pe VPS

```bash
ssh ovh
docker --version              # ≥ 24.0
docker compose version        # v2.x
nginx -v                      # ≥ 1.18
certbot --version             # ≥ 1.21
```

### 2. Creează folder layout pe VPS

```bash
ssh ovh "mkdir -p ~/web/erp.paff.ro/{repo,data/{live,backup,filestore},logs}"
```

Layout final pe VPS:
```
~/web/erp.paff.ro/
├── repo/                    # git clone al repo-ului (rsync target)
│   ├── docker-compose.yml
│   ├── docker-compose.prod.yml
│   ├── docker/
│   ├── src/
│   ├── config/
│   ├── patches/
│   └── ...
├── data/
│   ├── live/                # PostgreSQL data dir
│   ├── backup/              # pg_dump-uri rotite
│   └── filestore/           # Odoo attachments
├── logs/                    # Odoo logs
└── .env                     # Production secrets (NU în git)
```

### 3. DNS

```bash
dig erp.paff.ro
# A record → VPS IP
```

## First-time deploy

### Step 1 — Clone repo pe VPS

```bash
ssh ovh
cd ~/web/erp.paff.ro
git clone --recurse-submodules \
    git@github.com:poparcosmin/odoo.git \
    repo
```

> Notă: `--recurse-submodules` pentru OCA/l10n-romania.

### Step 2 — Generate production secrets

```bash
ssh ovh
cd ~/web/erp.paff.ro/repo
cp config/env.template ../.env
ln -sf ../.env .env             # symlink: compose folosește .env din repo dir

scripts/generate-secrets.sh --update
# Editează manual restul: TELEGRAM_BOT_TOKEN, ANAF_SPV_*, MEDUSA_API_KEY, etc.
```

> **CRITIC:** completează `.env` complet înainte de Step 4. `ODOO_DB_PASSWORD` și `ODOO_MASTER_PASSWORD` sunt obligatorii.

### Step 3 — Build image

```bash
cd ~/web/erp.paff.ro/repo
docker compose -f docker-compose.yml -f docker-compose.prod.yml build odoo
```

Așteaptă ~3-5 minute (build cu locale RO + python deps).

### Step 4 — Init DB

```bash
# Start postgres only
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d postgres

# Așteaptă healthy
until docker exec paff-erp-postgres pg_isready -U odoo_user; do sleep 2; done

# Start Odoo container fără auto-init (init DB manual)
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d odoo

# Init DB cu localizare RO + 17 module l10n_ro
scripts/init-db.sh paff_prod
# Așteaptă 5-10 minute (install module-uri)
```

### Step 5 — Configure nginx

```bash
sudo cp docs/deploy/nginx-erp-paff-ro.conf.example \
        /etc/nginx/sites-available/erp.paff.ro
sudo ln -s /etc/nginx/sites-available/erp.paff.ro \
           /etc/nginx/sites-enabled/erp.paff.ro
sudo nginx -t
sudo systemctl reload nginx
```

### Step 6 — Get SSL cert

```bash
sudo certbot --nginx -d erp.paff.ro \
             --non-interactive --agree-tos -m poparcosmin@gmail.com
```

certbot ar trebui să modifice automat config-ul nginx să includă SSL config-ul. Dacă deja l-ai pus în config tu, certbot detectează și nu duplică.

### Step 7 — systemd unit (auto-start at boot)

```bash
sudo cp docs/deploy/systemd-paff-odoo.service \
        /etc/systemd/system/paff-odoo.service
sudo systemctl daemon-reload
sudo systemctl enable paff-odoo.service
sudo systemctl start paff-odoo.service
sudo systemctl status paff-odoo
```

### Step 8 — Validation

Browser: `https://erp.paff.ro/web/login`

```bash
# Login admin / <ce ai setat în .env la prima init>
# SCHIMBĂ parola admin imediat în Settings → Users
```

```bash
# Smoke test din terminal (din local, prin SSH tunnel)
ssh ovh -L 8310:127.0.0.1:8310
# În alt terminal local:
curl -sf http://localhost:8310/web/health
```

## Update routine (after first deploy)

```bash
ssh ovh
cd ~/web/erp.paff.ro/repo
git pull origin main
git submodule update --remote --merge

# Rebuild dacă Dockerfile s-a schimbat
docker compose -f docker-compose.yml -f docker-compose.prod.yml build odoo

# Restart
sudo systemctl restart paff-odoo

# Verify
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs --tail=50 odoo
```

### Update addons custom (paff_*)

```bash
docker exec paff-erp-odoo \
  odoo -c /etc/odoo/odoo.conf \
       -u paff_<modul> \
       -d paff_prod \
       --stop-after-init
sudo systemctl restart paff-odoo
```

### Update OCA l10n-romania

```bash
cd ~/web/erp.paff.ro/repo
git submodule update --remote src/addons-vendor/l10n-romania
git add src/addons-vendor/l10n-romania
git commit -m "chore: bump OCA l10n-romania"
git push origin main

# Pe VPS:
docker exec paff-erp-odoo \
  odoo -c /etc/odoo/odoo.conf \
       -u l10n_ro_account,l10n_ro_partner_create_by_vat,... \
       -d paff_prod \
       --stop-after-init
sudo systemctl restart paff-odoo
```

## Failure modes

### Container nu pornește
```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs --tail=100 odoo
# Check: locale ro_RO.UTF-8 generated? envsubst rendered config? PG reachable?
```

### nginx 502 Bad Gateway
```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
# Odoo down? Restart: sudo systemctl restart paff-odoo
# Check upstream: curl -sf http://127.0.0.1:8310/web/health
```

### Schema migration falls (după upgrade)
- Restore DB din backup: `scripts/restore-db.sh data/backup/daily/<latest> paff_prod`
- Pin version anterior: vezi runbook upgrade.md
- Investighează: `docker exec paff-erp-odoo odoo --stop-after-init -d paff_prod -u <module>`

### Backup restore pe VPS
```bash
cd ~/web/erp.paff.ro/repo
scripts/restore-db.sh ~/backups/paff_prod-YYYYMMDD-HHMMSS paff_prod
sudo systemctl restart paff-odoo
```

## Backup pe VPS (cron)

```bash
crontab -e
```

Adaugă:
```cron
# Daily 02:00 — Odoo backup (PG + filestore)
0 2 * * * cd /home/cosmin/web/erp.paff.ro/repo && scripts/backup-db.sh paff_prod --type daily >> /home/cosmin/web/erp.paff.ro/logs/backup.log 2>&1

# Weekly Monday 03:00
0 3 * * 1 cd /home/cosmin/web/erp.paff.ro/repo && scripts/backup-db.sh paff_prod --type weekly >> /home/cosmin/web/erp.paff.ro/logs/backup.log 2>&1

# Monthly day 1 04:00
0 4 1 * * cd /home/cosmin/web/erp.paff.ro/repo && scripts/backup-db.sh paff_prod --type monthly >> /home/cosmin/web/erp.paff.ro/logs/backup.log 2>&1
```

## Offsite backup (recomandat)

```bash
# Setup rsync nightly la storage extern (ex: Hetzner Storage Box)
crontab -e
```

```cron
# Daily 05:00 — sync backup la storage offsite
0 5 * * * rsync -az --delete /home/cosmin/web/erp.paff.ro/data/backup/ user@storage.example.com:paff-odoo-backups/
```
