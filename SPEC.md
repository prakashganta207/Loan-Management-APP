# Loan & Chit Management App — Frozen Spec (v1 Rebuild)

This freezes the database schema and screen-by-screen UX before implementation, per the blueprint's recommendation. Any schema change after this point should be made via a migration, not a silent edit.

**Current schema version: 2.** v1 → v2 added `chit_groups.commission_mode` and `chit_auctions.winner_payout` (see §1a).

---

## 1. Database Schema (SQLite via sqflite)

All tables use `id INTEGER PRIMARY KEY AUTOINCREMENT`. Dates stored as ISO-8601 strings (`yyyy-MM-dd` or full timestamp). Money stored as REAL (rupees, 2 decimals enforced in app layer, not DB).

### users
| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| username | TEXT | |
| password_hash | TEXT | salted hash, never plaintext |
| pin_hash | TEXT NULL | optional quick-unlock PIN |
| biometric_enabled | INTEGER | 0/1 |
| created_at | TEXT | |

### borrowers
| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| name | TEXT NOT NULL | |
| phone | TEXT | |
| address | TEXT | |
| notes | TEXT | |
| is_archived | INTEGER | 0/1, default 0 |
| created_at | TEXT | |
| updated_at | TEXT | |

### loans
| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| borrower_id | INTEGER FK -> borrowers.id | ON DELETE RESTRICT |
| loan_name | TEXT NOT NULL | e.g. "Shop Loan" |
| total_payable | REAL NOT NULL | |
| daily_payment | REAL NOT NULL | lender-chosen, not forced to total/100 |
| duration_days | INTEGER NOT NULL | |
| fine_per_day | REAL NOT NULL DEFAULT 0 | configurable, not hardcoded |
| start_date | TEXT NOT NULL | |
| status | TEXT | 'active' \| 'completed' \| 'archived' |
| created_at | TEXT | |
| updated_at | TEXT | |

Derived (computed at read time from `loan_payments`, never trusted as stored truth): `total_paid`, `total_fine`, `outstanding_balance = total_payable - total_paid`.

### loan_payments
| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| loan_id | INTEGER FK -> loans.id | ON DELETE CASCADE |
| payment_date | TEXT NOT NULL | the schedule date this entry covers |
| scheduled_amount | REAL NOT NULL | |
| amount_paid | REAL NOT NULL DEFAULT 0 | |
| fine_amount | REAL NOT NULL DEFAULT 0 | |
| status | TEXT | 'paid' \| 'missed' \| 'partial' |
| note | TEXT | |
| created_at | TEXT | |

A ₹900 payment against a ₹300/day loan creates **three** `loan_payments` rows (one per covered day) so the ledger stays auditable per the blueprint's multi-day rule.

### chit_groups
| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| chit_name | TEXT NOT NULL | |
| chit_value | REAL NULL | optional per blueprint |
| number_of_members | INTEGER NOT NULL | |
| duration_months | INTEGER NOT NULL | |
| commission_percent | REAL NOT NULL DEFAULT 0 | |
| commission_mode | TEXT NOT NULL DEFAULT 'from_dividend' | v2. 'from_dividend' \| 'from_winner' (CHECK). New chits default to 'from_winner' in the app; the DB default keeps pre-v2 chits on their original maths. Locked after the first auction. |
| start_date | TEXT NOT NULL | |
| status | TEXT | 'active' \| 'completed' \| 'archived' |
| created_at | TEXT | |
| updated_at | TEXT | |

### chit_members
| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| chit_group_id | INTEGER FK -> chit_groups.id | ON DELETE CASCADE |
| member_name | TEXT NOT NULL | |
| phone | TEXT NULL | |
| membership_status | TEXT | 'active' \| 'inactive' |
| has_won | INTEGER | 0/1 — enforces the no-repeat-winner rule |
| joined_at | TEXT | |

### chit_auctions
| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| chit_group_id | INTEGER FK -> chit_groups.id | ON DELETE CASCADE |
| month_number | INTEGER NOT NULL | 1-based |
| auction_date | TEXT NOT NULL | |
| winner_member_id | INTEGER FK -> chit_members.id | must have has_won=0 at entry time |
| winning_amount | REAL NOT NULL | organizer enters this, not the discount |
| discount | REAL | = chit_value - winning_amount |
| commission_amount | REAL | = chit_value * commission_percent / 100 |
| dividend_pool | REAL | from_dividend: = discount - commission_amount; from_winner: = discount |
| dividend_per_member | REAL | = dividend_pool / number_of_members |
| winner_payout | REAL NULL | v2. What the winner receives: from_dividend = winning_amount; from_winner = winning_amount - commission_amount. Backfilled to winning_amount for pre-v2 rows. |
| created_at | TEXT | |

One row per `(chit_group_id, month_number)`, unique constraint.

### 1a. Auction maths (commission modes)
`winning_amount` is the auctioned price the winner accepted. Always: `discount = chit_value - winning_amount`, `commission = chit_value × commission_percent / 100`, `base = chit_value / number_of_members`. All values rounded to 2 decimals; `ChitCalculator` is the only place this is computed.

| | from_dividend (members bear commission) | from_winner (winner bears commission) |
|---|---|---|
| dividend_pool | discount − commission | discount |
| dividend_per_member | pool / members | pool / members |
| each member pays | base − dividend_per_member (= (winning_amount + commission) / members) | winning_amount / members |
| winner receives | winning_amount | winning_amount − commission |
| rejected when | discount < commission | winner receives ≤ 0 |

Example — value 100000, 20 members, won at 80000, 5% commission:
from_dividend → dividend/member 750, each pays 4250, winner gets 80000, commission 5000;
from_winner → dividend/member 1000, each pays 4000, winner gets 75000, commission 5000.
With 0% commission both modes give the same split.

### Schema migrations
- **v1 → v2:** `ALTER TABLE chit_groups ADD COLUMN commission_mode TEXT NOT NULL DEFAULT 'from_dividend' CHECK (...)`; `ALTER TABLE chit_auctions ADD COLUMN winner_payout REAL`; backfill `winner_payout = winning_amount`. Fresh installs create the v1 tables and then run the same migration, so new and upgraded databases are identical.
- Backups record `schema_version`. Restore accepts v1 and v2 backups (missing columns take the defaults above) and rejects anything newer than the app's schema.

### chit_contributions
| column | type | notes |
|---|---|---|
| id | INTEGER PK | |
| chit_group_id | INTEGER FK -> chit_groups.id | ON DELETE CASCADE |
| chit_member_id | INTEGER FK -> chit_members.id | ON DELETE CASCADE |
| month_number | INTEGER NOT NULL | |
| amount | REAL NOT NULL | |
| status | TEXT | 'paid' \| 'pending' |
| payment_date | TEXT NULL | |
| created_at | TEXT | |

One row per `(chit_member_id, month_number)`, unique constraint.

### app_settings (key-value)
| column | type | notes |
|---|---|---|
| key | TEXT PK | e.g. 'upi_id', 'upi_payee_name', 'last_backup_at', 'pin_enabled' |
| value | TEXT | |

### Relationships
```
borrowers (1) ── (N) loans (1) ── (N) loan_payments
chit_groups (1) ── (N) chit_members
chit_groups (1) ── (N) chit_auctions ── winner → chit_members
chit_groups (1) ── (N) chit_contributions ── chit_members
```

### Business rules baked into the schema layer (not just UI)
1. A `chit_member` with `has_won = 1` cannot be set as `winner_member_id` on a new auction for the same chit (checked in `chit_service`, enforced with a transaction).
2. `loans.status` transitions only `active -> completed -> archived`; never deleted.
3. `loan_payments` are append-only; corrections are new rows with a note, not edits to history (keeps the ledger auditable, matching the blueprint's "auditable ledger" requirement).
4. All money fields are non-negative; validated in the service layer before insert.

---

## 2. Screen-by-Screen Spec

### Splash
- Shows app name/logo, checks whether a user record + password exist.
- Routes to Login if a user exists, else to first-run Login/Setup (create local password).

### Login
- If first run: create username + password (+ optional PIN) fields, large touch targets.
- If returning: password field, optional biometric prompt if enabled, "Forgot password" resets via a recovery flow that wipes local auth only (data stays, since app doesn't hold money/accounts remotely).

### Dashboard
- Header stat row: Today's Collection (expected vs collected), Pending Borrowers count, Active Loans count, Active Chits count.
- "Today's Collection Schedule" list: borrower name, amount due, paid/missed toggle, tap-through to payment entry.
- Quick action buttons: Loan Management, Chit Management, Chit Calculator, Reports.

### Borrower List
- Search/filter bar, list of borrowers (name, phone, outstanding balance badge), FAB to add borrower.

### Add/Edit Borrower
- Fields: Name (required), Phone, Address, Notes. Large form, minimal typing.

### Borrower Profile
- Header: name, phone, address, notes (edit icon).
- Tabs/sections: Loans (list with status chips), Payment History (chronological), Fines total, Outstanding Balance (prominent).

### Loan List
- Filter by status (Active/Completed/Archived), list shows borrower + loan name + outstanding + next due.

### Add Loan
- Fields: Borrower (picker, or "new borrower" inline), Loan name, Total payable, Daily payment, Duration (days, auto-suggested from total/daily but editable), Fine/day, Start date, Status defaults Active.

### Loan Details
- Summary card: total payable, paid so far, outstanding, fines, days remaining.
- Actions: Mark Payment (today), View Payment History, Trigger UPI Payment, Mark Completed/Archive (when outstanding = 0).

### Payment Entry
- Prefilled scheduled amount (daily_payment), editable amount field, date defaults today (editable for backdating missed days), fine auto-calculated from days-late × fine_per_day but editable, Save.
- If amount paid > scheduled, offer to apply the excess to future scheduled days per the multi-day rule.

### Payment History
- Chronological list per loan: date, scheduled, paid, fine, status chip.

### Chit List
- Filter by status, list shows chit name, value, members, current month/duration.

### Create Chit
- Fields: Chit name, Chit value (optional), Number of members, Duration (months), Commission %, Commission paid by (Winner — members pay auctioned price ÷ members / Members — deducted from dividend; defaults to Winner), Start date.

### Chit Details
- Summary: value, members count, current month, total commission earned, total dividends paid.
- Tabs: Members, Auctions, Contributions.

### Add Member
- Fields: Member name (required), Phone (optional). Enforces member count against `number_of_members`.

### Auction Entry
- Select month, select winner (excludes members with has_won=1), enter winning amount.
- Live-calculated preview: commission mode, Discount, Commission, Dividend Pool, Dividend/Member, Winner receives, Each member pays with a one-line formula (e.g. "₹80,000 ÷ 20 = ₹4,000") before save.
- On save: marks winner has_won=1, locks the month's auction row.

### Contribution Tracking
- Grid/list per month: member name, amount, paid/pending toggle, payment date.

### Auction History
- List of past auctions per chit: month, winner, winning amount, winner payout, dividend/member, commission.

### Chit Calculator (standalone, no persistence)
- Inputs: Chit value, Number of members, Winning amount, Commission %, Commission paid by (same toggle as Create Chit).
- Outputs (live): Discount, Commission, Dividend Pool, Dividend/Member, Winner receives, Effective contribution per member with its formula.

### Reports
- Daily: today's collected vs expected, list of today's transactions.
- Monthly: month picker, total collected, total fines, chit contributions collected that month.
- Overall: total money lent, total collected, outstanding balance, total fines, active/closed loan counts, active chit count, total commissions, total dividends paid.

### Settings
- Backup: "Export Backup Now" (writes a timestamped JSON/db file to device storage), shows last backup date, reminder toggle.
- Restore: pick a backup file, confirm (destructive — double confirmation), restore.
- Security: change password, enable/disable PIN, enable/disable biometric (if device supports).
- App Info: version, about, UPI payee ID/name configuration (used by the payment trigger).

---

## 3. UPI Payment Flow (spec)
```
Loan Details / Payment Entry
  → "Pay via UPI" button (only if UPI ID configured in Settings)
  → builds upi://pay?pa={upi_id}&pn={payee_name}&am={amount}&cu=INR&tn={loan_name}
  → url_launcher opens installed UPI app
  → app returns to foreground
  → dialog: "Did the payment go through?" [Confirm Paid] [Not Yet]
  → Confirm Paid records a loan_payment row with status=paid, note="UPI"
```
No automated verification in V1 — matches the blueprint's stated limitation.

---

## 4. Non-goals for this rebuild (V1)
- No payment gateway (Razorpay etc.)
- No borrower/member accounts or borrower-facing app
- No cloud backup/sync
- No push notifications (structure will leave room for it, but not implemented)
