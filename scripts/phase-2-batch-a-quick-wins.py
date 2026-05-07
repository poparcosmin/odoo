"""Phase 2 Batch A — Quick wins (E2 + E7 + T6).

E2: Payment Terms cleanup (zero-credit decision)
E7: Export Rights restriction (Admin + Contabil only)
T6: 5 Activity Types customizate PAFF
"""

# ─── E2 — Payment Terms cleanup ───────────────────────────────────────
print("=" * 60)
print("E2 — Payment Terms cleanup (zero-credit business model)")
print("=" * 60)

# Find toate payment terms existente
all_terms = env['account.payment.term'].search([])
print(f"Found {len(all_terms)} payment terms total")

# Toate cu T15/T30/T45/T60 sau "EOM" (End of Month) → DEACTIVATE (NU șterge — păstrăm istoric)
terms_to_disable = []
keep_terms = []
for term in all_terms:
    name = term.name or ''
    # Keep: Immediate Payment + 100% Advance — match cu zero-credit model
    if any(k in name.lower() for k in ['immediate', 'imediat', 'advance', 'avans']):
        keep_terms.append(term)
    else:
        terms_to_disable.append(term)

print(f"\nKEEP active: {len(keep_terms)}")
for t in keep_terms:
    print(f"  ✓ {t.name} (id={t.id}, active={t.active})")

print(f"\nDISABLE (zero-credit, keep history): {len(terms_to_disable)}")
for t in terms_to_disable:
    if t.active:
        t.write({'active': False})
        print(f"  → DEACTIVATED: {t.name} (id={t.id})")
    else:
        print(f"  - already inactive: {t.name}")

# Asigur că exists "Plată imediată" (default + zero-credit standard)
imediata = env['account.payment.term'].search([('name', 'ilike', 'imediat')], limit=1)
if not imediata:
    # Caut "Immediate Payment" și redenumesc
    immediate_en = env['account.payment.term'].search([('name', 'ilike', 'immediate')], limit=1)
    if immediate_en:
        immediate_en.with_context(lang='ro_RO').write({'name': 'Plată imediată'})
        print(f"\n[E2] Renamed 'Immediate Payment' → 'Plată imediată' (ro_RO)")

# Plus add "Plată în avans 100%" dacă lipsește
advance = env['account.payment.term'].search([('name', 'ilike', 'avans')], limit=1)
if not advance:
    advance = env['account.payment.term'].create({
        'name': 'Plată în avans 100%',
        'note': 'Pre-plată completă înainte de producție/livrare. Standard PAFF zero-credit.',
        'active': True,
        'line_ids': [(0, 0, {
            'value': 'percent',
            'value_amount': 100.0,
            'nb_days': 0,
        })],
    })
    print(f"\n[E2] Created 'Plată în avans 100%' (id={advance.id})")
else:
    print(f"\n[E2] 'Plată în avans 100%' deja există (id={advance.id})")

# ─── E7 — Export Rights restriction ───────────────────────────────────
print("\n" + "=" * 60)
print("E7 — Export Rights → Admin + Contabil only")
print("=" * 60)

allow_export = env.ref('base.group_allow_export')
print(f"base.group_allow_export id={allow_export.id}")

# Get current users în group
users_with_export = allow_export.user_ids
print(f"Currently {len(users_with_export)} users have export rights:")
for u in users_with_export:
    print(f"  - {u.login} (id={u.id})")

# Identify users who SHOULD have export (Admin + Contabil)
target_users = env['res.users'].search([
    '|',
    ('login', '=', 'paff.office@gmail.com'),  # Admin
    ('login', '=', 'contabil_demo'),           # Contabil template
])

# Remove from non-target users
for user in users_with_export:
    if user.id not in target_users.ids and user.id != env.ref('base.user_admin').id:
        # Check dacă e member prin alt grup — dacă da, nu remove
        if allow_export in user.group_ids:
            user.group_ids = [(3, allow_export.id)]
            print(f"  → REMOVED export from: {user.login}")

# Add la target users
for user in target_users:
    if allow_export not in user.group_ids:
        user.group_ids = [(4, allow_export.id)]
        print(f"  → ADDED export to: {user.login}")
    else:
        print(f"  ✓ {user.login} already has export")

# ─── T6 — 5 Activity Types customizate PAFF ──────────────────────────
print("\n" + "=" * 60)
print("T6 — 5 Activity Types customizate PAFF")
print("=" * 60)

ActivityType = env['mail.activity.type']

paff_activities = [
    {
        'name': 'Verificare CIF ANAF',
        'summary': 'Validează partener nou cu ANAF API înainte ofertă',
        'delay_count': 1,
        'delay_unit': 'days',
        'res_model': 'res.partner',
        'category': 'default',
    },
    {
        'name': 'Confirmare livrare șofer',
        'summary': 'Confirmă cu șoferul ridicarea + AWB',
        'delay_count': 1,
        'delay_unit': 'days',
        'res_model': 'stock.picking',
        'category': 'default',
    },
    {
        'name': 'Apel încasare T-3 zile',
        'summary': 'Apel client 3 zile post-livrare verifică plată recepționată',
        'delay_count': 3,
        'delay_unit': 'days',
        'res_model': 'sale.order',
        'category': 'default',
    },
    {
        'name': 'Vizită client mare',
        'summary': 'Vizită fizică clienți B2B major (>50k RON/an)',
        'delay_count': 7,
        'delay_unit': 'days',
        'res_model': 'res.partner',
        'category': 'default',
    },
    {
        'name': 'Reconcile bank statement',
        'summary': 'Procesare extras BCR/ING/BT + match plăți cu pro-forma',
        'delay_count': 1,
        'delay_unit': 'days',
        'res_model': 'account.bank.statement',
        'category': 'default',
    },
]

created = 0
existing = 0
for spec in paff_activities:
    existing_at = ActivityType.search([('name', '=', spec['name'])], limit=1)
    if existing_at:
        print(f"  ✓ '{spec['name']}' deja există (id={existing_at.id})")
        existing += 1
    else:
        new_at = ActivityType.create({
            'name': spec['name'],
            'summary': spec['summary'],
            'delay_count': spec['delay_count'],
            'delay_unit': spec['delay_unit'],
            'res_model': spec['res_model'],
            'category': spec['category'],
        })
        print(f"  → Created '{spec['name']}' (id={new_at.id}, model={spec['res_model']})")
        created += 1

print(f"\n[T6] Activity Types: {created} created, {existing} existing")

# ─── Commit ──────────────────────────────────────────────────────────
env.cr.commit()

print("\n" + "=" * 60)
print("✅ Phase 2 Batch A APPLIED")
print("=" * 60)
print(f"E2: {len(keep_terms)} active terms, {len(terms_to_disable)} disabled")
print(f"E7: {len(target_users)} users have export rights")
print(f"T6: {created + existing}/5 PAFF activity types ready")
