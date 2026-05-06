# Runbook — Incident Response Odoo

## Severity matrix

| Severity | Trigger | SLA | Notification |
|----------|---------|-----|--------------|
| **SEV-1** | Production down (HTTP 5xx >50%, DB unreachable) | 15 min response, 1h resolution | Telegram urgent + SMS |
| **SEV-2** | Functionality broken (login fail, integration Medusa down) | 1h response, 4h resolution | Telegram |
| **SEV-3** | Performance degraded (response time 5x normal) | 4h response, 24h resolution | Telegram normal |
| **SEV-4** | Cosmetic / non-blocking | Next business day | Email digest |

## SEV-1: Production down

### Triage (primii 5 min)
```bash
# 1. Container alive?
docker ps --filter "name=paff-odoo" --format "{{.Status}}"

# 2. Healthcheck pass?
docker exec paff-odoo /opt/paff-healthcheck.sh; echo "exit=$?"

# 3. Logs ultima ora
docker logs --since=1h paff-odoo 2>&1 | grep -iE "error|critical|exception" | tail -50

# 4. PostgreSQL alive?
docker exec paff-odoo pg_isready -h postgres -U odoo_user
```

### Quick recovery options (în ordine de invazivitate)

**Option A: restart container (low risk)**
```bash
docker compose --profile erp restart odoo
```

**Option B: rollback ultima imagine (medium risk)**
```bash
git log --oneline docker/Dockerfile -5
git revert <last_dockerfile_commit>
docker compose --profile erp up -d --build odoo
```

**Option C: restore DB din backup (high risk — pierderi posibile)**
```bash
# 1. Check ultimele backup-uri
ls -lat data/backup/daily/ | head -5

# 2. Restore (CONFIRMĂ înainte!)
scripts/restore-db.sh data/backup/daily/paff_prod-YYYYMMDD paff_prod

# 3. Restart Odoo
docker compose --profile erp restart odoo
```

### Post-incident
- [ ] Notify users: status page + Telegram channel
- [ ] Capture logs: `docker logs paff-odoo > /tmp/incident-$(date +%s).log`
- [ ] Open postmortem doc: `docs/postmortems/YYYY-MM-DD-titlu.md`
- [ ] Identify trigger: deployment recent? cron job? volum traffic?

## SEV-2: Login broken

```bash
# Verifică dacă DB e accesibilă din container
docker exec paff-odoo psql -h postgres -U odoo_user -d paff_prod -c "SELECT count(*) FROM res_users;"

# Verifică dacă session-store funcționează
docker exec paff-odoo ls -la /var/lib/odoo/sessions/

# Verifică Caddy → Odoo upstream
docker exec paff-caddy curl -sI http://odoo:8069/web/login
```

## SEV-2: Integration Medusa ↔ Odoo broken

```bash
# Test JSON-RPC din Medusa side
curl -X POST http://erp.paff.ro/jsonrpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"call","params":{"service":"common","method":"version"}}'

# Verifică Odoo logs pentru erori RPC
docker logs paff-odoo --since=30m | grep -i "rpc\|xmlrpc"

# Verifică certificatele dacă trafic e cross-server
```

## SEV-3: Performance degraded

```bash
# Top slow queries
docker exec paff-odoo psql -h postgres -U odoo_user -d paff_prod -c "
  SELECT query, calls, mean_exec_time, total_exec_time
  FROM pg_stat_statements
  ORDER BY mean_exec_time DESC LIMIT 10;
"

# Workers status
docker exec paff-odoo ps -ef | grep odoo

# Memory usage
docker stats paff-odoo --no-stream
```

## Backup verification (rulat săptămânal)

```bash
# Pick un backup random
backup=$(ls data/backup/daily/ | shuf -n 1)

# Restore în DB temporar
scripts/restore-db.sh "data/backup/daily/$backup" paff_test_restore

# Smoke test
docker exec paff-odoo \
  odoo shell -d paff_test_restore --no-http \
  <<< 'env["res.users"].search_count([])'

# Cleanup
docker exec paff-odoo psql -h postgres -U odoo_user -d postgres \
  -c "DROP DATABASE paff_test_restore;"
```

## Contacts

- **On-call:** poparcosmin@gmail.com
- **PostgreSQL admin:** vezi `~/Work/Ecommerce/docs/runbooks/postgres.md`
- **Caddy / DNS:** vezi `~/Work/Ecommerce/docs/runbooks/caddy.md`
- **ANAF API status:** https://anaf.ro/anaf/internet/ANAF/servicii_online/
