# Runbook — Restore & Disaster Recovery

> **RTO target:** 4h (full system restore)
> **RPO target:** 24h (daily backup cycle)
> **Tier:** B2B mission-critical (Cod Fiscal RO 5 ani retention)

## Strategie 3-2-1

```
Original (paff_prod în Postgres + filestore în volume Docker)
   ↓
Local backup (host disk):  data/backup/{daily,weekly,monthly,env,manual}/
   ↓
Offsite backup (Google Drive):  drive:paff-odoo-backup/
```

## Backup pipeline running (cron daily 03:00)

```
03:00 daily  scripts/backup-master.sh
  ├── 03:00:00  scripts/backup-db.sh paff_prod {daily|weekly|monthly}
  │             ├── pg_dump (custom format)
  │             ├── tar filestore via docker exec
  │             ├── MANIFEST + sha256sum
  │             └── GFS retention (7/4/60)
  ├── 03:00:30  scripts/backup-env.sh (age-encrypted .env)
  ├── 03:00:35  scripts/verify-git-backup.sh
  ├── monthly:  scripts/verify-backup.sh (restore test)
  ├── weekly:   scripts/sync-offsite.sh (rclone → drive:)
  └── 03:05:00  scripts/notify.sh (Telegram + email)
```

## Disaster scenarios

### Scenario 1 — DB corrupt (PostgreSQL crash) — RTO 30 min

**Detection:** Odoo error 500 cu PG-related stack trace, sau `docker compose logs postgres` arată corruption.

**Steps:**

```bash
# 1. Stop Odoo (preserve filestore intact)
docker compose stop odoo

# 2. Find latest GOOD backup
ls -lt data/backup/daily/ | head -5

# 3. Restore (interactive prompt — confirm by typing DB name)
scripts/restore-db.sh data/backup/daily/paff_prod-YYYYMMDD-HHMMSS paff_prod

# 4. Restart Odoo
docker compose up -d odoo

# 5. Verify (browser http://localhost:8310/web/login)
docker compose logs -f odoo --tail=50
```

**Verification:**
- Login OK paff.office@gmail.com
- Companies → PAFF SRL data intact
- Sales journal code='FAC' present
- Last invoices visible

**Post-incident:**
- Notify cabinet contabilitate dacă a fost afectat day end-of-month
- Document în mail.thread pe res.company message_post()

### Scenario 2 — Filestore lost (atașamente PDF rupte) — RTO 15 min

**Detection:** Click pe attachment în Odoo → 404 sau "File not found". Imagini partener missing.

**Steps:**

```bash
# 1. Identify backup cu filestore intact (verify checksums.sha256)
cd data/backup/daily/paff_prod-YYYYMMDD-HHMMSS
sha256sum -c checksums.sha256

# 2. Extract filestore în container (PRESERVE existing DB)
docker exec paff-erp-odoo \
  rm -rf /var/lib/odoo/filestore/paff_prod
docker exec -i paff-erp-odoo \
  tar xzf - -C /var/lib/odoo/filestore < filestore.tar.gz

# 3. Restart Odoo (clear cache)
docker compose restart odoo

# 4. Test attachment
# Browser: deschide o factură veche cu PDF → download
```

**NU restore DB** — pierdeți modificările între backup și acum.

### Scenario 3 — Code lost (server compromise / git delete) — RTO 1h

**Detection:** Repo local șters / corrupt. paff_* addons missing din container.

**Steps:**

```bash
# 1. Clone repo from GitHub origin
cd ~/Work/
mv Odoo Odoo.compromised  # preserve forensics
git clone --recurse-submodules git@github.com:poparcosmin/odoo.git Odoo
cd Odoo

# 2. Restore .env (encrypted backup)
scripts/backup-env.sh --restore data/backup/env/daily/env-YYYYMMDD-HHMMSS.tar.gz.age /tmp/env-restored
cp /tmp/env-restored/.env ./.env
shred -u /tmp/env-restored/.env  # secure delete

# 3. Re-clone src/odoo (Layer 1 read-only upstream)
git clone --depth 1 --branch 19.0 https://github.com/odoo/odoo.git src/odoo

# 4. Rebuild containers
docker compose build --no-cache odoo
docker compose up -d

# 5. Verify
docker compose logs -f odoo --tail=50
curl -s -w "\nHTTP %{http_code}\n" http://localhost:8310/web/login -o /dev/null
```

**Note:** DB intactă (PostgreSQL volume `paff_pgdata` persistent dacă disk-ul a supraviețuit).

### Scenario 4 — Full disaster (server lost) — RTO 4h

**Detection:** Server hardware fail, datacenter incident, ransomware lockdown, sau accidental `rm -rf /`.

**Steps:**

```bash
# 1. Provision new server (Ubuntu 24.04 LTS, OVH/Hetzner/etc.)
# 2. Install Docker + Docker Compose v2
sudo apt update && sudo apt install -y docker.io docker-compose-v2

# 3. Install rclone + age
sudo apt install -y rclone
curl -LO https://github.com/FiloSottile/age/releases/latest/download/age-v1.1.1-linux-amd64.tar.gz
tar xzf age-v1.1.1-linux-amd64.tar.gz && sudo mv age/age* /usr/local/bin/

# 4. Restore age private key from OFFLINE backup
# (paper safe / Bitwarden secure note — tu ai cheia privată)
mkdir -p ~/.age
nano ~/.age/paff-backup.key  # paste from offline source
chmod 600 ~/.age/paff-backup.key

# 5. Configure rclone Google Drive remote
rclone config  # interactive; remote name 'drive', auth flow OAuth

# 6. Pull all backup dates
mkdir -p ~/Work/Odoo/data/backup
rclone copy drive:paff-odoo-backup ~/Work/Odoo/data/backup/ \
  --progress --transfers=4

# 7. Clone code from GitHub
cd ~/Work/Odoo
git clone --recurse-submodules git@github.com:poparcosmin/odoo.git .
git clone --depth 1 --branch 19.0 https://github.com/odoo/odoo.git src/odoo

# 8. Restore .env (encrypted)
scripts/backup-env.sh --restore data/backup/env/daily/env-LATEST.tar.gz.age /tmp/env-restored
cp /tmp/env-restored/.env .env

# 9. Build + start (without Odoo until DB restore)
docker compose up -d postgres
docker compose ps  # wait for postgres healthy

# 10. Restore DB (latest daily)
LATEST=$(ls -1dt data/backup/daily/paff_prod-* | head -1)
scripts/restore-db.sh "$LATEST" paff_prod

# 11. Start Odoo
docker compose up -d odoo

# 12. Verify
curl -s http://localhost:8310/web/login | grep -q "Odoo" && echo "✓ Login page loads"
```

**Post-incident:**
- Inform legal (data breach notification ANAF + ANPC dacă aplică)
- Update access credentials (admin password rotate, OAuth tokens revoke)
- Forensics audit pe vechiul server (dacă recuperabil)

## Backup integrity checks

### Manual verification (oricând)

```bash
# Test latest daily restore
scripts/verify-backup.sh

# Test specific backup
scripts/verify-backup.sh data/backup/monthly/paff_prod-20260101-030000

# Verify all backups (heavy — durează ~1 oră pentru toate)
for b in data/backup/daily/paff_prod-*; do
  scripts/verify-backup.sh "$b" || echo "FAIL: $b"
done
```

### Auto via cron

```cron
# Cron entry already installed:
0 3 * * *   ~/Work/Odoo/scripts/backup-master.sh

# Detect type pe DOM/DOW:
#   DOM=01     → monthly (+verify + offsite)
#   DOW=Sunday → weekly (+offsite)
#   else       → daily
```

## .env restore procedure

```bash
# Latest encrypted backup
LATEST_ENV=$(ls -1t data/backup/env/daily/env-*.tar.gz.age | head -1)

# Decrypt cu private key
scripts/backup-env.sh --restore "$LATEST_ENV" /tmp/env-restored

# Move la root (cu attention — overwrites current .env)
diff /tmp/env-restored/.env ./.env  # review delta
cp /tmp/env-restored/.env ./.env

# Cleanup
shred -u /tmp/env-restored/.env
```

## Age key management

**CRITICAL:** dacă pierzi `~/.age/paff-backup.key`, **TOATE backup-urile encrypted devin inrecuperabile**.

### Backup strategy pentru age key

1. **Print pe hârtie** (small font, base64 of file content) — păstrare în safe fizic
2. **Bitwarden secure note** — sau alt password manager cu MFA
3. **Encrypted USB stick** — păstrat la cabinet contabilitate / lawyer / safe

### Generate new key (în caz de rotation)

```bash
# Backup vechiul key
cp ~/.age/paff-backup.key ~/.age/paff-backup-OLD-$(date +%Y%m%d).key

# Generate new
age-keygen -o ~/.age/paff-backup.key
chmod 600 ~/.age/paff-backup.key

# RE-ENCRYPT toate backup-urile env existente cu key-ul nou
for f in data/backup/env/daily/env-*.tar.gz.age data/backup/env/monthly/env-*.tar.gz.age; do
  age -d -i ~/.age/paff-backup-OLD-*.key "$f" \
    | age -r $(grep "^# public key:" ~/.age/paff-backup.key | cut -d' ' -f4) \
    > "${f}.new"
  mv "${f}.new" "$f"
done

# Sync re-encrypted la Google Drive
scripts/sync-offsite.sh
```

## Notifications setup (TODO USER, one-time)

Backup pipeline notifies prin Telegram + email. Pentru a activa:

### Telegram (5 min)

1. Open Telegram app → search `@BotFather` → /newbot
2. Choose name (e.g., "PAFF Backup Bot") + username (e.g., `paff_backup_bot`)
3. Receive bot token (`1234567:AAAA...`) — salvează la `PAFF_TG_BOT_TOKEN` în `.env`
4. /start to your bot in Telegram (your DM)
5. Open `https://api.telegram.org/bot<TOKEN>/getUpdates` — find `chat.id` (your user id)
6. Save la `PAFF_TG_CHAT_ID` în `.env`

### Gmail App Password (5 min)

1. https://myaccount.google.com/apppasswords (necesită 2FA enabled pe Gmail account)
2. Select "Mail" + "Other (PAFF Backup)" → Generate
3. Copy 16-char password (`xxxx xxxx xxxx xxxx`)
4. Salvează la `PAFF_SMTP_PASS` în `.env` (FĂRĂ spaces — `xxxxxxxxxxxxxxxx`)

### Test

```bash
scripts/notify.sh --severity ok "Test notification" "Setup complete"
```

Should deliver Telegram + email în <5 secunde.

## Troubleshooting

### "FAIL: rclone remote 'drive' not configured"

```bash
rclone config
# n) New remote
# name> drive
# Storage> drive (Google Drive)
# Follow OAuth flow (browser)
```

### Backup runs but FAIL în log

```bash
# Latest log
tail -100 logs/backup-$(date +%Y%m%d).log

# Common issues:
# 1. Disk full → df -h ~/Work/Odoo/data/backup/
# 2. Postgres container down → docker compose ps
# 3. Permission denied filestore → docker exec paff-erp-odoo ls -la /var/lib/odoo/filestore
```

### Restore fails cu "database paff_prod is being accessed by other users"

```bash
# Force disconnect alle sesiuni
docker exec paff-erp-postgres \
  psql -U odoo_user -d postgres \
       -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='paff_prod';"

# Re-run restore
scripts/restore-db.sh ...
```

### Sync to Google Drive fails

```bash
# Check rclone token
rclone config show drive | grep -E "token|expiry"

# Re-auth dacă token expired
rclone config reconnect drive:
```

## Schedule summary

| Job | Frequency | Command |
|---|---|---|
| Backup DB + filestore | Daily 03:00 | `backup-master.sh` (auto-detects type) |
| Backup `.env` (encrypted) | Daily 03:00 | inclus în `backup-master.sh` |
| Git verify | Daily 03:00 | inclus în `backup-master.sh` |
| Restore test | Monthly 1st 03:00 | inclus în `backup-master.sh` |
| Sync offsite (Google Drive) | Sunday + monthly 1st | inclus în `backup-master.sh` |
| Notification (success/fail) | După fiecare run | `notify.sh` (Telegram + email) |

## RTO/RPO summary

| Scenario | RTO target | RPO target | Notes |
|---|---|---|---|
| DB corrupt | 30 min | 24h | Local backup acceptabil |
| Filestore lost | 15 min | 24h | DB intactă, restore doar tar.gz |
| Code lost | 1h | 0h (git) | Re-clone GitHub + rebuild |
| Full disaster | 4h | 24h | Provision + offsite restore |

## References

- [scripts/backup-db.sh](../../scripts/backup-db.sh)
- [scripts/restore-db.sh](../../scripts/restore-db.sh)
- [scripts/backup-env.sh](../../scripts/backup-env.sh)
- [scripts/verify-backup.sh](../../scripts/verify-backup.sh)
- [scripts/verify-git-backup.sh](../../scripts/verify-git-backup.sh)
- [scripts/sync-offsite.sh](../../scripts/sync-offsite.sh)
- [scripts/backup-master.sh](../../scripts/backup-master.sh)
- [scripts/notify.sh](../../scripts/notify.sh)
- [config/env.template](../../config/env.template)
