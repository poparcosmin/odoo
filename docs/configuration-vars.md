# PAFF Odoo — Configuration Variables Master List

> **Regula PAFF #1** (vezi `CLAUDE.md` → Configuration Centralization):
> Toate variabilele de configurare cross-addon trăiesc într-un singur loc.
> Acest fișier e lista master a tuturor variabilelor declarate, cu owner addon
> și status (pending / live).

> **Status pattern technical**: în așteptarea cercetării R-002 (vezi
> `docs/research-backlog.md`), folosim interim `ir.config_parameter` cu prefix
> `paff_*`. Pattern final (A: `res.config.settings` extension vs B: model
> `paff.config` dedicat) decidem după R-002.

---

## Convenție naming

```
paff_<addon_short>_<setting>
```

- `<addon_short>`: 1-2 cuvinte care identifică addon-ul (`telegram`, `anaf`, `fan`, `netopia`, `e_factura`)
- `<setting>`: snake_case, descriptiv

**Exemple corecte:**
- `paff_telegram_bot_token`
- `paff_anaf_certificate_path`
- `paff_fan_api_key`

**Exemple GREȘITE:**
- `telegram_bot_token` (lipsește prefix `paff_`)
- `paff.telegram.bot_token` (dot notation, NU snake_case)
- `TG_TOKEN` (uppercase, prescurtare ne-clară)
- `paff_settings_telegram_token` (`settings_` extra, redundant)

---

## Variabile declarate (per addon)

### `paff_telegram` — Telegram bot integration

> **Status:** pending (R-001 research)
> **Decizia finală variabile vine după research.**

Probabile (de validat în research):

| Variable | Type | Sensitive? | Default | Description |
|---|---|---|---|---|
| `paff_telegram_bot_token` | str | ✅ Yes | — | Token de la BotFather (`<bot_id>:<secret>`) |
| `paff_telegram_webhook_url` | str | No | — | URL HTTPS pentru webhook (ex: `https://erp.paff.ro/telegram/webhook`) |
| `paff_telegram_webhook_secret` | str | ✅ Yes | random 32-char | Secret pentru validare callback Telegram |
| `paff_telegram_mode` | str | No | `polling` | Mode: `webhook` (production) sau `polling` (dev) |
| `paff_telegram_admin_chat_id` | int | No | — | Chat ID admin pentru alerte critice |
| `paff_telegram_default_chat_id` | int | No | — | Chat ID default pentru notificări (orders, invoices) |
| `paff_telegram_rate_limit_rpm` | int | No | `30` | Max requests per min (Telegram default 30) |

### `paff_anaf` — ANAF integration (CIF lookup, e-Factura SPV)

> **Status:** pending (probabil din module l10n_ro_message_spv + l10n_ro_partner_create_by_vat existing — verifică dacă suprascriem sau extindem)

Probabile:

| Variable | Type | Sensitive? | Default | Description |
|---|---|---|---|---|
| `paff_anaf_api_endpoint` | str | No | `https://webservicesp.anaf.ro/...` | API endpoint ANAF |
| `paff_anaf_spv_certificate_path` | str | No | `/etc/odoo/certs/anaf-spv.p12` | Path PKCS12 cert |
| `paff_anaf_spv_certificate_password` | str | ✅ Yes | — | Password pentru cert |
| `paff_anaf_company_cif` | str | No | (din company) | CIF companie pentru auth |
| `paff_anaf_environment` | str | No | `production` | `production` sau `test` |

### `paff_fan` — FAN Courier integration

> **Status:** scoped, not implemented

Placeholder (de detaliat la implementare):

| Variable | Type | Sensitive? | Default | Description |
|---|---|---|---|---|
| `paff_fan_api_key` | str | ✅ Yes | — | API key FAN Courier |
| `paff_fan_username` | str | No | — | Username FAN |
| `paff_fan_default_service` | str | No | `STANDARD` | Service code default |

### `paff_netopia` — NETOPIA Payments integration

> **Status:** scoped, not implemented (Medusa ↔ Odoo ar putea avea responsabilitatea aici, decizie deschisă)

Placeholder:

| Variable | Type | Sensitive? | Default | Description |
|---|---|---|---|---|
| `paff_netopia_signature_key` | str | ✅ Yes | — | Cheie signature webhook |
| `paff_netopia_merchant_id` | str | No | — | ID merchant |
| `paff_netopia_environment` | str | No | `sandbox` | `sandbox` sau `live` |

### `paff_email` — Email branding (deja activ)

> **Status:** ✅ live (configured 2026-05-06)

| Variable | Type | Sensitive? | Default | Description |
|---|---|---|---|---|
| `mail.default.from` | str | No | `paff.office@gmail.com` | Email default From pentru notificări |
| `mail.from.filter` | str | No | `paff.office@gmail.com` | Filter SMTP server matching |
| `mail.catchall.domain` | str | No | `gmail.com` | Domain bounce handling |
| `mail.bounce.alias` | str | No | `paff.office` | Alias bounce |
| `google_gmail_client_id` | str | No | (set) | OAuth client ID Google |
| `google_gmail_client_secret` | str | ✅ Yes | (set) | OAuth client secret |

> Note: aceste variabile folosesc convenție Odoo standard (`mail.*`, `google_gmail_*`),
> NU prefix `paff_*`. Excepție acceptată — sunt parte din core Odoo, nu addon PAFF.

---

## Variabile shared / cross-addon

> Variabile folosite de mai multe addon-uri PAFF. Declarate o singură dată,
> referențiate prin `paff_shared_*`.

| Variable | Type | Sensitive? | Default | Description |
|---|---|---|---|---|
| `paff_shared_company_cif` | str | No | (din `res.company`) | CIF principal PAFF SRL — folosit de ANAF, e-Factura, FAN |
| `paff_shared_company_email` | str | No | `paff.office@gmail.com` | Email contact PAFF — From pentru email-uri trimise |
| `paff_shared_debug_mode` | bool | No | `false` | Toggle global pentru logging verbose în addon-uri PAFF |
| `paff_shared_timezone` | str | No | `Europe/Bucharest` | Timezone fallback când nu vine din user |

---

## Lifecycle workflow

### Adăugare variabilă nouă

1. **Editează acest fișier** — adaugă rând în tabel cu addon owner + descriere
2. **Setează valoarea** prin `ir.config_parameter` (interim până la R-002):
   ```python
   env['ir.config_parameter'].sudo().set_param('paff_<addon>_<setting>', value)
   ```
3. **Citește valoarea**:
   ```python
   val = env['ir.config_parameter'].sudo().get_param('paff_<addon>_<setting>', default)
   ```
4. **Documentează în addon `__manifest__.py`** câmpul `external_dependencies` dacă e nevoie de deps Python suplimentare

### Migrare la pattern final (după R-002)

Când research-ul R-002 produce decizia A vs B:

- **Dacă A** (`res.config.settings` extension): migrare automată, parametrii deja în `ir.config_parameter` rămân; trebuie doar UI-views noi
- **Dacă B** (`paff.config` model): migrare prin script — citește din `ir.config_parameter`, scrie în `paff.config` records, drop key-urile vechi

### Verificare consistență

Script de audit (TODO: scripts/audit-config-vars.sh):
```bash
# Listează toate variabilele paff_* din DB:
docker exec paff-erp-postgres psql -U odoo_user -d paff_prod -c "
  SELECT key, CASE WHEN length(value) > 30 THEN '<redacted>' ELSE value END
  FROM ir_config_parameter
  WHERE key LIKE 'paff_%' OR key IN ('mail.default.from', 'mail.catchall.domain')
  ORDER BY key;
"
```

Compară output-ul cu acest fișier — orice mismatch = inconsistență de fixat.

---

## Anti-patterns interzise

- ❌ Hardcoding tokens/keys în cod Python (`TELEGRAM_TOKEN = "abc123"` în model.py)
- ❌ Câmpuri tehnice pe `res.company` cu prefix lipsă (`res.company.telegram_token` — punct nepotrivit, conflict potențial)
- ❌ Pagini Settings separate per addon (`paff_telegram` cu propriul tab Settings, `paff_anaf` cu altul)
- ❌ Naming inconsistent (`telegram_token` într-un loc, `paff_tg_token` în altul, `TG_BOT` în .env)
- ❌ Stocare cleartext credentials în câmpuri text fără markare sensitive
- ❌ Adăugare variabilă fără update în acest fișier
