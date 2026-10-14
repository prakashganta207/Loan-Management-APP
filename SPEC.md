# Loan & Chit Management App — Spec (v1.0.0)

This freezes the database schema and screen-by-screen UX before implementation, per the blueprint's recommendation. Any schema change after this point should be made via a migration, not a silent edit.

**App version: 1.1.0. Current schema version: 3.** v1 → v2 added `chit_groups.commission_mode` and `chit_auctions.winner_payout` (see §1a); v2 → v3 added monthly loans and the chit-winner loan setup (see "Schema migrations"). This document describes what the v1.1.0 code does; open questions are listed in `AUDIT.md` under "Needs owner decision".

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
| daily_payment | REAL NOT NULL | **the instalment**: per day for daily loans, **per month for monthly loans** (name kept: older Android SQLite can't rename columns). Code reads it as `Loan.installmentAmount`. |
| duration_days | INTEGER NOT NULL | **number of instalments**: days for daily loans, **months for monthly loans**. Code reads it as `Loan.installmentCount`. |
| fine_per_day | REAL NOT NULL DEFAULT 0 | daily loans only (0 for monthly) |
| repayment_type | TEXT NOT NULL DEFAULT 'daily' | v3. 'daily' \| 'monthly' (CHECK). `Loan.isMonthly`. |
| late_interest_percent | REAL NOT NULL DEFAULT 0 | v3. Monthly loans: simple interest % per month on an overdue instalment. |
| grace_days | INTEGER NOT NULL DEFAULT 0 | v3. Monthly loans: days after a due date before late interest starts. |
| source_chit_auction_id | INTEGER NULL | v3. Set when the loan was created for a chit auction winner. Unique when not null (partial index), no FK (restore inserts loans before chits). |
| start_date | TEXT NOT NULL | daily: first collection day; monthly: **first due date** |
| status | TEXT | 'active' \| 'completed' \| 'archived' |
| created_at | TEXT | |
| updated_at | TEXT | |

Derived (computed at read time from `loan_payments`, never trusted as stored truth): `total_paid`, `total_fine`, `outstanding_balance = total_payable - total_paid`.

#### Loan schedule rules (`LoanService.computeSummary` / `recordPayment`)
One schedule, two instalment periods. Everything below applies to daily and monthly loans alike; "instalment" means a day's payment for daily loans and a month's for monthly loans.
- **Instalment *i*** (0-based) is due on `slotDate(i)`:
  - daily: `start_date + i days`;
  - monthly: `start_date + i months`, the day clamped to the month's last day, **always computed from `start_date`** (never chained): 31 Jan → 28 Feb (29 in a leap year) → 31 Mar → 30 Apr.
  - Monthly payments and missed marks are only accepted on an instalment due date.
- Instalment *i* is due `min(instalment, total_payable − instalment × i)`, so the last instalment can be smaller (₹1,000 at ₹300/day → 300, 300, 300, 100).
- **Days covered / instalments paid** = instalments within `installmentCount` whose payments add up to their due amount.
- **Next due date** = the first instalment not fully paid (the scan continues past `installmentCount` for loans that run over); none once the loan is cleared.
- **Days behind** = days from the next due date to today (0 if it is today or later). **Overdue instalments** = instalments due before today that are not fully paid (Loan Details shows "N instalments overdue · D days late" for monthly loans).
- **Payments left** = ⌈outstanding ÷ instalment⌉.
- **Recording money** (all amounts rounded to paise with `round2`):
  - amount must be > 0 and ≤ outstanding; fine ≥ 0; the schedule day must not be before `start_date`; only active loans accept payments.
  - With the split (default), the amount fills the chosen instalment first (topping up a partial one), then each following instalment: one ledger row per instalment (₹900 at ₹300/day = 3 rows; 3 months at once = 3 rows), status `paid` when that instalment is complete or the loan is cleared, else `partial`.
  - With the split switched off, the whole amount is one row on the chosen day; the balance is right but the schedule (next due / days covered) does not move past that day.
  - The late charge goes in `fine_amount` on the first row only; the lender can edit the suggestion. Late days = payment date − instalment due date.
    - **Daily — fine** = late days × `fine_per_day`.
    - **Monthly — late interest** = `round2(unpaid part of that instalment × late_interest_percent / 100 × max(0, late days − grace_days) / 30)`. Simple interest on the overdue instalment only: never on the whole loan, never compounding. Example: ₹5,000 at 2%/month, 45 days late → ₹150.00; with 15 grace days → ₹100.00; on time → ₹0.
  - **Accrued late interest** (monthly, Loan Details "Late interest due so far"): the same formula summed over every overdue instalment as of today. It is information only; it is charged when the late payment is recorded.
- **Missed day**: a zero-amount `missed` row, at most once per schedule day, not allowed on a fully paid day or before `start_date`. It does not change the balance.
- **Corrections**: there is no correction entry yet — a saved payment cannot be reversed (see AUDIT A3).

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
| loan_setup_status | TEXT NOT NULL DEFAULT 'pending' | v3. 'pending' \| 'created' \| 'dismissed' (CHECK). Every saved auction starts 'pending' (a "Waiting for setup" item); auctions from before v3 are 'pending' too. |
| loan_id | INTEGER NULL FK -> loans.id | v3. The loan set up for the winner. |
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
- **v2 → v3:** `loans` gets `repayment_type` (DEFAULT 'daily'), `late_interest_percent`, `grace_days` (DEFAULT 0) and `source_chit_auction_id` (+ a unique partial index); `chit_auctions` gets `loan_setup_status` (DEFAULT 'pending') and `loan_id`. Existing loans become daily loans and existing auctions become waiting items. History is not edited.
- Backups record `schema_version`. Restore accepts v1, v2 and v3 backups (missing columns take the defaults above) and rejects anything newer than the app's schema.

### 1b. Chit winner → loan setup
- Saving an auction makes the winner a **pending** item: Loans → "Waiting for setup" shows winner, chit, month and prize; the dashboard shows "N chit winners need loan setup".
- **Setup** (Loan Setup screen) creates the loan and sets the auction to `created` with `loan_id` **in one transaction**; the auction must still be `pending` (checked by the update's WHERE clause, plus the unique index on `loans.source_chit_auction_id`), so a double tap or a second setup can never create two loans. If anything fails, nothing is saved (including a borrower created for the winner).
- Defaults: repayment type Monthly; total payable = prize (`winner_payout`, else `winning_amount`), editable; first due date = auction date + 1 month (clamped); grace days 0; loan name "<chit> — month N prize".
- **Borrower**: a non-archived borrower with the member's phone, or — when the member has no phone — the same name (case-insensitive) is pre-selected; otherwise a new borrower is created from the member's name and phone. Any existing borrower can be picked instead.
- **Remaining chit instalments for this member** (info only) = months from the auction month to the end of the chit, minus that member's contributions already marked paid in those months.
- **Not a loan** (with confirmation) sets the item to `dismissed`; the Loans screen's "Dismissed" filter lists them with **Restore** (back to `pending`).

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
3. `loan_payments` are append-only (SQLite triggers block UPDATE and DELETE; DELETE on `loans` is blocked too). History is never edited. A correction-entry mechanism is not built yet (AUDIT A3, needs owner decision).
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
- Banner "N chit winners need loan setup" when any auction is waiting (opens Loans).
- "Today's Collection Schedule" list: every active loan that has started, except loans already cleared and loans paid ahead (next due date after today) with nothing collected today — so a monthly loan appears only when an instalment is due today or overdue. Each row shows borrower, amount due, paid/missed buttons, and taps through to payment entry (long-press opens Loan Details).
  - daily: due = `min(daily instalment, outstanding + collected today)`;
  - monthly: due = unpaid part of the next due instalment + collected today (capped by outstanding); if today's money already covered it, due = collected today (shows as collected).
  - The quick "paid" button records the still-due amount against the next due instalment.
- Collected = loan money recorded today (`created_at` today, fines excluded); expected = sum of the rows' amounts due; pending borrowers = borrowers with a row that is neither collected nor marked missed today.
- The quick paid/missed buttons ignore repeat taps while a save is running.
- Quick action buttons: Loan Management, Chit Management, Chit Calculator, Reports.

### Borrower List
- Search/filter bar, list of borrowers (name, phone, outstanding balance badge), FAB to add borrower.

### Add/Edit Borrower
- Fields: Name (required), Phone, Address, Notes. Large form, minimal typing.

### Borrower Profile
- Header: name, phone, address, notes (edit icon).
- Tabs/sections: Loans (list with status chips), Payment History (chronological), Fines total, Outstanding Balance (prominent).

### Loan List
- "Waiting for setup" section at the top (chit winners: name, chit, month, prize; tap → Loan Setup; ✕ → "Not a loan"), with a Waiting / Dismissed filter (Dismissed items have Restore).
- Filter by status (Active/Completed/Archived), list shows borrower + loan name + "₹X / day" or "₹X / month" + outstanding + next due (+ days behind, or overdue instalments for monthly).

### Add Loan
- Fields: Borrower (picker, or "new borrower" inline), Loan name, then the shared loan-terms widget: **Repayment type** (Daily / Monthly) first.
  - Daily: Total payable, Daily payment, Duration (days, auto-suggested from total ÷ daily but editable), Fine/day, Start date.
  - Monthly: Total payable, Number of months, Monthly instalment (auto-suggested as total ÷ months, editable), First due date (default one month from today), Late interest % per month, Grace days (default 0).
- Status defaults Active.

### Loan Setup (chit winner)
- Header: winner, chit + month, auction date, prize received, remaining chit instalments for this member (info).
- Borrower picker (matched borrower pre-selected, or "New borrower: <member>"), Loan name, then the same loan-terms widget (Monthly pre-selected, total = prize, first due = auction date + 1 month). Create loan → opens the new loan. "Not a loan" dismisses with confirmation.

### Loan Details
- Summary card: total payable, paid so far, outstanding, days behind, payments left, next due, plus:
  - daily: fines collected, "₹X / day", fine per late day, start date, days covered;
  - monthly: late interest collected, **late interest due so far** (accrued, unpaid), "₹X / month", late interest % and grace days, first due date, instalments paid, "N instalments overdue · D days late".
- Chit-sourced loans show "From chit: <name>, month N", linking to the chit.
- Actions: Record Payment, Mark Missed (next unpaid instalment up to today; monthly only when one is due), Pay via UPI (only when a UPI ID is set), Mark Completed (when outstanding = 0), Archive (when completed). Payment history is a section on this screen.

### Payment Entry
- Daily: prefilled amount `min(daily instalment, outstanding)`; schedule day defaults to the first unpaid day (date picker, not before the start date); "Fine" = late days × fine_per_day.
- Monthly: prefilled amount = unpaid part of the next due instalment; "Instalment this covers" picker listing unpaid instalments (number + due date); "Late interest" pre-filled with the late-interest formula on that instalment's unpaid part.
- All editable; Save. "Collect via UPI, then save" appears only when a UPI ID is set.
- If the amount is more than one instalment, offer to apply the excess to the following days / instalments per the multi-instalment rule.

### Payment History
- Chronological list per loan: date, scheduled, paid, fine ("Late interest" for monthly loans), status chip.

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
- Grid/list per month: member name, amount, paid/pending toggle, payment date. The list is created at chit value ÷ members; recording that month's auction re-prices still-pending rows to the calculator's "each member pays" amount. Rows already ticked paid keep their amount (AUDIT A7, needs owner decision).

### Auction History
- List of past auctions per chit: month, winner, winning amount, winner payout, dividend/member, commission, and the loan status chip (Waiting / Loan created / Dismissed). Tap: Waiting → Loan Setup, Loan created → the loan.

### Chit Calculator (standalone, no persistence)
- Inputs: Chit value, Number of members, Winning amount, Commission %, Commission paid by (same toggle as Create Chit).
- Outputs (live): Discount, Commission, Dividend Pool, Dividend/Member, Winner receives, Effective contribution per member with its formula.

### Reports
- Daily: loan money and fines recorded on the day (`created_at`), chit contributions marked paid that day, and its ledger entries; expected is shown for today only.
- Monthly: month picker, loan money and fines recorded that month, chit contributions marked paid that month, commission of auctions dated that month, number of payment entries.
- Overall: total lent (sum of total payable, all loans), total collected, outstanding (active loans), total fines, active/closed loan counts, active chit count, total commissions, total dividends (sum of dividend pools), contributions collected.

### Settings
- Backup: "Export Backup Now" (writes a timestamped JSON/db file to device storage), shows last backup date, reminder toggle.
- Restore: pick a backup file, confirm (destructive — double confirmation), restore. Restore is one transaction that keeps the login, accepts v1 and v2 backups and rejects newer ones; a damaged file shows "This backup file is damaged or not from this app. Nothing was changed."
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
  → Confirm Paid records the payment through the normal rules (multi-day split, note="UPI"); a row is `paid`, or `partial` if it covers less than that day's amount
```
No automated verification in V1 — matches the blueprint's stated limitation.

---

## 4. Non-goals for this rebuild (V1)
- No payment gateway (Razorpay etc.)
- No borrower/member accounts or borrower-facing app
- No cloud backup/sync
- No push notifications (structure will leave room for it, but not implemented)
