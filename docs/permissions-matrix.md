# Permissions Matrix — PAFF Odoo

> **Status:** v1 — applied 2026-05-07 în paff_prod
> **Etapa:** 6 (Users & Permissions UP-FRONT) per checklist v2
> **Capacitate planificată:** 2-3 vânzători + 1 contabil intern + 2 manageri + 1 admin

## Roluri (4 total)

| Rol | Demo template | Capacitate | Active users |
|---|---|---|---|
| Admin | (existing) `paff.office@gmail.com` | 1 | 1 (Cosmin) |
| Manager | `manager_demo` (id=7, INACTIVE) | 2 | 0 (TODO onboard) |
| Contabil | `contabil_demo` (id=6, INACTIVE) | 1 | 0 (TODO onboard) |
| Vânzător/Operator | `vanzator_demo` (id=5, INACTIVE) | 2-3 | 0 (TODO onboard) |

> Demo users sunt INACTIVE (nu pot loga, nu consum licență). Servesc ca template pentru onboarding — copy groups la user real.

## Group composition per rol

### Vânzător/Operator (combined per decizie D2)

```
+ base.group_user                          # Internal User mandatory
+ sales_team.group_sale_salesman           # Sales: OWN documents only
+ stock.group_stock_user                   # Inventory: zilnic operations
+ purchase.group_purchase_user             # Purchase: NIR recepții
+ account.group_account_invoice            # Invoice: DRAFT only (NU post)
+ base.group_partner_manager               # Create clienți noi
```

### Contabil (intern per decizie D3)

```
+ base.group_user
+ account.group_account_user               # Full accounting features
+ account.group_account_secured            # Inalterability (lock dates)
+ sales_team.group_sale_salesman_all_leads # Read ALL sales
+ purchase.group_purchase_user             # Vendor bills
+ stock.group_stock_user                   # Stock valuation reports
```

### Manager (cu pricelist + product cost edit per decizie D4)

```
+ base.group_user
+ sales_team.group_sale_manager            # Sales Administrator
+ stock.group_stock_manager                # Inventory Administrator
+ purchase.group_purchase_manager          # Purchase Administrator
+ account.group_account_readonly           # Read accounting (NU edit)
+ base.group_partner_manager
+ product.group_product_manager            # Manage products + pricelist + cost
```

### Admin

```
+ base.group_user
+ base.group_system                        # Technical Settings
+ base.group_erp_manager                   # Access Rights (manage users)
+ account.group_account_manager            # Accounting Admin
+ sales_team.group_sale_manager
+ stock.group_stock_manager
+ purchase.group_purchase_manager
+ product.group_product_manager
+ l10n_ro_config.group_ro_menus
+ spreadsheet_dashboard.group_dashboard_manager
```

**Best practice:** folosit DOAR pentru config tasks. Pentru work zilnic, manager-ul ar trebui să folosească user-ul Manager (NU Admin). Reduce blast radius la accidentală config change.

## CRUD Matrix per modele core

| Model / Acțiune | Vânzător | Contabil | Manager | Admin |
|---|:---:|:---:|:---:|:---:|
| `res.partner` (clienți) — create | ✅ | ✅ | ✅ | ✅ |
| `res.partner` (clienți) — edit own | ✅ | ✅ | ✅ | ✅ |
| `res.partner` — edit ALL | ❌ | ✅ | ✅ | ✅ |
| `sale.order` — create draft | ✅ | ❌ | ✅ | ✅ |
| `sale.order` — confirm own | ✅ | ❌ | ✅ | ✅ |
| `sale.order` — confirm all | ❌ | ❌ | ✅ | ✅ |
| `account.move` — create draft (out_invoice) | ✅ | ✅ | ❌ | ✅ |
| `account.move` — POST | ❌ | ✅ | ❌ | ✅ |
| `account.move` — edit posted | ❌ | ✅ (until lock) | ❌ | ✅ |
| `account.move` — read all | ❌ | ✅ | ✅ readonly | ✅ |
| `account.payment` — register | ❌ | ✅ | ❌ | ✅ |
| `account.bank.statement` — reconcile | ❌ | ✅ | ❌ | ✅ |
| `tax_lock_date` — set | ❌ | ✅ | ❌ | ✅ |
| `account.report` (Tax Report) — view | ❌ | ✅ | ✅ readonly | ✅ |
| `stock.move` — basic transferuri | ✅ | ❌ | ✅ | ✅ |
| `stock.move` — large adjustments | ❌ | ❌ | ✅ | ✅ |
| `stock.location` — create new | ❌ | ❌ | ✅ | ✅ |
| `stock.warehouse` — config | ❌ | ❌ | ✅ | ✅ |
| `purchase.order` — RFQ + draft | ✅ | ❌ | ✅ | ✅ |
| `purchase.order` — confirm | ❌ | ❌ | ✅ | ✅ |
| `product.template` — create + edit | ❌ | ❌ | ✅ | ✅ |
| `product.template` — edit cost | ❌ | ❌ | ✅ | ✅ |
| `product.pricelist` — create + edit | ❌ | ❌ | ✅ | ✅ |
| `res.users` — create / edit | ❌ | ❌ | ❌ | ✅ |
| `res.groups` — manage | ❌ | ❌ | ❌ | ✅ |
| Settings → General | ❌ | ❌ | ❌ | ✅ |
| Settings → Technical (cron, etc.) | ❌ | ❌ | ❌ | ✅ |
| Apps → Install/Uninstall module | ❌ | ❌ | ❌ | ✅ |

## Workflow approval per scenario

### Scenario 1 — Comandă vânzare normală (≤ threshold)

```
Vânzător → ofertă → email client → confirm → sale.order
       → recepție/livrare stoc → factură DRAFT
Contabil → review factură → POST → email client cu PDF
       → încasare bank → reconcile
```

### Scenario 2 — Comandă mare (≥ threshold X RON, TBD)

```
Vânzător → ofertă → MANAGER REVIEW (manual workflow) → confirm
... (rest same as Scenario 1)
```

> Threshold X TBD per business decision. Recomand 50.000 RON net pentru carton B2B.

### Scenario 3 — Achiziție materii prime (hârtie testliner/fluting)

```
Vânzător → identifică nevoie → RFQ draft (purchase.order)
Manager → review + select furnizor → confirm RFQ → PO
Recepție: Vânzător/Operator → NIR (stock receipt)
Contabil → bill furnizor → reconcile
```

### Scenario 4 — Closing lună fiscală

```
Contabil (final lună N):
  1. Verify Tax Report (Accounting → Reports)
  2. Export → completează manual D300 în SPV ANAF (USB token)
  3. Upload XML D394 (DUKIntegrator)
  4. După confirm ANAF → set Tax Lock Date = 31 zilei N
  5. Mail summary la Manager + Admin (mail.activity)
```

### Scenario 5 — Onboarding angajat nou (Vânzător)

```
Admin:
  1. Settings → Users → Create User (sau copy groups din vanzator_demo)
  2. Set login = email corporate (ex: ion.popescu@paff.ro)
  3. Set name = nume real
  4. Activate (active = True)
  5. Send invitation email cu password reset
  6. Document în onboarding-checklist (TODO docs/onboarding.md)
Manager:
  7. Allocate sales team / leads
  8. Initial training pe Odoo + workflow PAFF
```

### Scenario 6 — Offboarding angajat (Vânzător leaves)

```
Admin (în 24h):
  1. Settings → Users → user.write({'active': False}) — keep history
  2. NU delete (audit trail RO 5 ani)
  3. Reassign open documents (sales orders, leads) la alt vânzător
  4. Revoke API keys (dacă există)
Manager:
  5. Review handover documents
  6. Update sales territory
```

## Escalation paths

| Situație | Cui escalez |
|---|---|
| Factură deja postată cu eroare valoare | Contabil → Manager → (rar) Admin pentru lock date override |
| User uitat plecat din companie | Manager → Admin pentru deactivare |
| Performance issue (cron blocked, queue full) | Admin |
| ANAF SPV token expired (90 zile) | Contabil → Admin pentru re-config |
| Backup failed (cron alert) | Admin (priority HIGH) |
| Suspect fraudulent activity | Manager → Admin → audit log review |

## MFA (Multi-Factor Authentication)

| Rol | MFA policy | Method | Justificare |
|---|---|---|---|
| Admin | ✅ MANDATORY | TOTP (Google Authenticator / Authy / Bitwarden TOTP) | Blast radius total |
| Manager | ✅ MANDATORY | TOTP | Decizii financiale + stock |
| Contabil | 🟡 highly recommended | TOTP | RO Cod Fiscal art. 79 — protecție 5 ani |
| Vânzător | 🔵 opt-in | TOTP | Operațional, low risk |

**Setup:** Settings → Account Security → Enable Two-Factor Authentication → scan QR → save backup codes.

**Backup codes:** stored offline (printed in safe sau Bitwarden secure note), NU în Odoo.

## Audit log retention

| Rol | Retention | Coverage |
|---|---|---|
| Admin | Forever | 100% changes (config, users, security) |
| Manager | 5 ani | 100% changes (financial decisions) |
| Contabil | 5 ani | 100% changes (RO fiscal mandatory) |
| Vânzător | 2 ani | Basic CRUD pe sale.order, partner |

> RO Cod Fiscal art. 79 cere 5 ani retention pe documente fiscale. Audit log e implicit prin `mail.thread` (mail.message records linked la account.move, sale.order, etc.). Retention vine prin backup GFS (data/backup/monthly/).

## Verification commands

```bash
# Toate users + groups (admin only)
docker exec paff-erp-postgres psql -U odoo_user -d paff_prod -c "
SELECT u.id, u.login, u.active,
  array_agg(d.module || '.' || d.name ORDER BY d.module) as groups
FROM res_users u
JOIN res_groups_users_rel r ON r.uid = u.id
JOIN ir_model_data d ON d.res_id = r.gid AND d.model = 'res.groups'
GROUP BY u.id, u.login, u.active
ORDER BY u.id;
"

# has_group() check pentru un user (Odoo shell)
docker exec -e ODOO_RC=/tmp/odoo.conf.rendered -i paff-erp-odoo odoo shell -d paff_prod --no-http <<'PYEOF'
u = env['res.users'].search([('login', '=', 'vanzator_demo')], limit=1)
print('Can sell own:', u.has_group('sales_team.group_sale_salesman'))
print('Can post invoice:', u.has_group('account.group_account_user'))
PYEOF
```

## Onboarding workflow (Admin task)

Când angajezi pe X (rol vânzător):

```python
# Odoo shell sau UI Settings → Users
demo = env.ref('base.user_admin')  # sau search vanzator_demo
new_user = env['res.users'].create({
    'login': 'ion.popescu@paff.ro',
    'name': 'Ion Popescu',
    'active': True,
    'group_ids': [(6, 0, demo_template_vanzator.group_ids.ids)],
    'lang': 'ro_RO',
    'tz': 'Europe/Bucharest',
    'notification_type': 'email',
})
new_user.action_reset_password()  # email cu password reset link
```

## Open questions / future improvements

- **Threshold approval comenzi mari**: 50.000 RON net e default propus, TBD business
- **Cabinet contabilitate extern** (când va fi cazul): user dedicat cu IP whitelist + access log review monthly
- **Field sales agent** (când scalezi): `sales_team.group_sale_salesman` doar, fără create partner (lead → manager assign)
- **Production worker** (când lansezi MRP): rol nou cu `mrp.group_mrp_user`
- **Audit log retention enforcement**: cron lunar care arhivează mail.message > X ani la cold storage
