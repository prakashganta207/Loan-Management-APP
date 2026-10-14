# Audit — Loan & Chit Manager (pre-v1.0.0)

Audited commit: `d8d2270` (schema v2, commission modes). Baseline: `flutter pub get` OK,
`flutter analyze` — no issues, `flutter test` — 36/36 passing.

Method: every file in `lib/` and `test/` was read. Behaviour was verified with scratch
probe tests (real numbers against an in-memory SQLite DB via `sqflite_common_ffi`) and a
widget probe that rendered all 19 screens at 360×640 dp, seeded (long names, ₹12,34,567.89
amounts, borrower with no phone, chit with no value) and empty, at text scale 1.0 and 1.3.
Probes that proved a bug are turned into permanent failing-first tests in Phase 2.

Source of truth: SPEC.md > README "Rules enforced below the UI" > chit rule (members pay
auctioned price ÷ members).

Severity: CRITICAL (wrong money / data loss) · HIGH (wrong result or crash) ·
MEDIUM (bad UX / edge case) · LOW (cosmetic). Category: BUG or RULE CHANGE.

---

## Findings

### A1 — CRITICAL · BUG — Double tap on dashboard "Mark paid" records the payment twice
- **Where:** `lib/screens/dashboard/dashboard_screen.dart:45` (`_quickPaid`), button at `:175`;
  same pattern for `_markMissed` at `:64`.
- **What:** The ✓ button has no in-flight guard. Two taps before the list reloads start two
  `recordPayment` calls; both are valid (the balance is still large), so two days are paid.
  The ledger is append-only and there is no way to reverse an entry (see A3), so the lender
  is stuck with money that was never received.
- **Proof:** widget probe on a ₹300/day loan: tap ✓ twice → `loan_payments` has **2 rows,
  ₹600 recorded** for one ₹300 collection.
- **Fix:** keep a `Set<int>` of loan ids being saved; ignore taps (and disable both buttons)
  for a loan while its save is running.

### A2 — HIGH · BUG — Borrowers who paid ahead show as due and pending on the dashboard
- **Where:** `lib/services/report_service.dart:141-151` (`todaySchedule`).
- **What:** Every active loan gets `due = daily payment` today, even when the next unpaid
  schedule day is in the future. A borrower who paid 3 days on Monday shows "due ₹300" on
  Tuesday, inflates "expected", counts as a pending borrower, and the ✓ button invites the
  lender to record a 4th day.
- **Proof:** loan ₹300/day started yesterday, ₹900 recorded yesterday (covers yesterday,
  today, tomorrow): next due = day after tomorrow, but dashboard shows 1 item, **due ₹300,
  expected ₹300, pending borrowers 1** (should be 0 / ₹0 / 0).
- **Fix:** skip a loan in today's schedule when its next due date is after today and nothing
  was collected from it today.

### A3 — HIGH · RULE CHANGE — There is no way to correct a mistaken payment
- **Where:** `lib/services/loan_service.dart:214` (amount must be > 0), DB
  `CHECK (amount_paid >= 0)`; README says "Corrections are new rows with a note".
- **What:** The ledger is append-only (correct), but nothing can append a *correcting* entry:
  negative amounts are rejected by the service and the DB, and there is no reversal status.
  Any typo (₹3,000 instead of ₹300) is permanent and makes the outstanding balance wrong.
- **Proof:** `recordPayment(amount: -300)` → `ValidationException`; no other write API exists.
- **Proposed fix (needs owner decision):** add a "Correct an entry" action that appends a
  `reversal` row (negative `amount_paid`, mandatory note, linked to the original row id).
  Needs a v3 migration (status + CHECK change) and conflicts with SPEC rule 4 ("all money
  fields are non-negative"), so it changes a business rule.

### A4 — MEDIUM · BUG — Async actions that touch the screen without a `mounted` check
- **Where:**
  - `lib/screens/settings/settings_screen.dart:66` (`_run` → `setState` after awaiting
    PIN/UPI/payee/fingerprint dialogs) and `:117` (`_restore` after the 2nd confirm)
  - `lib/screens/settings/settings_screen.dart:325-328` (`_PasswordDialog` catch → `setState`)
  - `lib/screens/chits/auction_entry_screen.dart:109` (`setState` after `confirmAction`)
  - `lib/screens/chits/chit_details_screen.dart:249` (`_toggle` → `_reload()` after await)
  - `lib/screens/auth/login_screen.dart:125` (`_forgot` → `setState` after `resetAuth`)
  - `lib/screens/auth/splash_screen.dart:30` (catch → `setState`)
- **What:** if the screen is closed while the await is pending, `setState` throws
  "setState() called after dispose()".
- **Proof:** code reading (the checklist requires every async action to be guarded).
- **Fix:** add `if (!mounted) return;` (or `if (mounted)`) before each of these.

### A5 — MEDIUM · BUG — Technical error text shown to the lender
- **Where:** `lib/widgets/common.dart:11` (`errorText` prints `Error: <exception>`),
  `lib/services/backup_service.dart:76-92` (restore does not validate rows),
  `lib/screens/auth/splash_screen.dart:30`.
- **What:** a damaged or hand-edited backup produces programmer messages.
- **Proof:** restoring a backup whose `loans` list holds a string →
  `Error: type 'String' is not a subtype of type 'Map<dynamic, dynamic>' in type cast`;
  a row with an unknown column → `Error: SqfliteFfiException(sqlite_error: 1, ...
  table borrowers has no column named nme, SQL logic error (code 1)`.
- **Fix:** restore validates that each table is a list of maps and wraps any failure in
  `ValidationException('This backup file is damaged or not from this app. Nothing was
  changed.')` (the transaction already rolls back). `errorText` shows a plain
  "Something went wrong. Please try again." with the technical detail on a second line.

### A6 — MEDIUM · BUG — Loan tile on Borrower Profile overflows with a larger phone font
- **Where:** `lib/screens/borrowers/borrower_profile_screen.dart:142` (trailing `Column`).
- **What:** at Android font size 1.3× on a 360 dp phone the status chip + balance column is
  2 px taller than the list tile → yellow/black overflow stripe.
- **Proof:** widget probe at 360×640, text scale 1.3: "A RenderFlex overflowed by 2.0 pixels
  on the bottom" (all 19 screens pass at 1.0×; this is the only failure at 1.3×).
- **Fix:** wrap the trailing column in `FittedBox(fit: BoxFit.scaleDown)`.

### A7 — MEDIUM · RULE CHANGE — A contribution paid before the auction keeps the old amount
- **Where:** `lib/services/chit_service.dart` `_ensureContributions` (only *pending* rows
  are re-priced after an auction).
- **What:** if the lender ticks a member as paid before recording that month's auction, the
  row stays at the full base (₹25,000) while everyone else drops to ₹20,000; the ₹5,000
  overpayment is not tracked anywhere.
- **Proof:** 4-member ₹1,00,000 chit, member 1 marked paid, then auction at ₹80,000 →
  amounts `25000/paid, 20000/pending ×3`.
- **Recommendation:** block "mark paid" for a month until its auction is recorded (simplest),
  or carry the difference as a credit to next month. Either changes how collection works.

### A8 — MEDIUM · RULE CHANGE — With "apply extra to following days" off, the schedule does not advance
- **Where:** `lib/services/loan_service.dart:254` / `computeSummary` (schedule is per day).
- **What:** ₹900 saved as one entry on day 1 of a ₹300/day loan: balance is right (₹2,100
  left) but next due stays day 2 and "days covered" = 1, so the dashboard asks for day 2.
- **Proof:** probe: 1 row, next due `2026-01-02`, covered 1.
- **Recommendation:** keep it (the switch is explicit and the helper text says "saved as a
  single entry"), or remove the switch so excess is always split.

### A9 — LOW · BUG — "Days covered" shows 3 of 4 on a fully paid loan
- **Where:** `lib/services/loan_service.dart:163-166`.
- **What:** when the total is not a multiple of the daily amount, the last instalment is
  smaller (₹1,000 at ₹300/day → 300, 300, 300, 100), but a day only counts as covered when
  a full ₹300 was paid.
- **Proof:** ₹900 + ₹100 → outstanding 0, cleared, last row `paid`, but `coveredDays = 3`.
- **Fix:** a day's scheduled amount is `min(daily, total − daily × dayIndex)`; count it
  covered when that amount is paid.

### A10 — LOW · BUG — Service accepts a payment dated before the loan starts
- **Where:** `lib/services/loan_service.dart:216` (`recordPayment`), `:283` (`markMissed`).
- **What:** the UI date picker blocks it, but the service doesn't. The money counts towards
  the balance, but the schedule never sees it (next due stays the start date).
- **Proof:** loan starting 2026-02-01, ₹300 on slot 2026-01-01 → accepted, paid ₹300,
  next due 2026-02-01, covered 0.
- **Fix:** reject a slot date earlier than the loan start date.

### A11 — LOW · BUG — Dashboard schedule row opens Loan Details, SPEC says Payment Entry
- **Where:** `lib/screens/dashboard/dashboard_screen.dart:191`.
- **SPEC:** Dashboard → "Today's Collection Schedule … tap-through to payment entry".
- **Fix:** tapping the row opens `PaymentEntryScreen` for that loan and refreshes after.

### A12 — LOW · BUG — UPI buttons shown when no UPI ID is configured
- **Where:** `lib/screens/loans/loan_details_screen.dart:192-199`,
  `lib/screens/loans/payment_entry_screen.dart:177-181`.
- **SPEC §3:** "Pay via UPI" button (only if UPI ID configured in Settings).
- **Fix:** show the UPI button only when a UPI ID is set.

### A13 — LOW · RULE CHANGE — UPI "Confirm paid" can record status `partial`, SPEC says `paid`
- **Where:** `lib/services/loan_service.dart:257` (status comes from the amount).
- **What:** a UPI payment smaller than the daily amount is stored as `partial` (ledger-correct),
  while SPEC §3 says "records a loan_payment row with status=paid, note=UPI".
- **Recommendation:** keep the ledger-correct status and reword SPEC §3.

### A14 — LOW · RULE CHANGE — Chit duration is not tied to the number of members
- **Where:** `lib/services/chit_service.dart` `_validate`.
- **What:** a 20-member chit can be created for 10 months (10 members never win) or 30 months
  (auctions run out after month 20).
- **Recommendation:** warn (not block) when duration ≠ members.

### A15 — LOW · RULE CHANGE — A fine cannot be collected on its own
- **Where:** `lib/services/loan_service.dart:214, 227`.
- **What:** a fine is only stored together with a payment of more than ₹0 and at most the
  outstanding balance, so a fine owed after the last instalment can't be recorded.
- **Recommendation:** allow a fine-only entry (amount 0, fine > 0).

### A16 — LOW · RULE CHANGE — "Total lent" is the total payable (includes interest)
- **Where:** `lib/services/report_service.dart:241`; schema has no principal column.
- **Recommendation:** keep the "Total lent (payable)" label, or add a principal field (schema v3).

---

## Chit rule check (source of truth #3)
**Implemented.** Per-chit `commission_mode`, default `from_winner` = "members pay auctioned
price ÷ members, commission deducted from the winner's prize"; old behaviour kept as
`from_dividend`; v1→v2 migration keeps existing chits on `from_dividend`; mode locks after
the first auction (`chit_service.dart` `updateChit`, test "commission mode can change before
the first auction, then locks").

Worked by hand — value ₹1,00,000, 20 members, auctioned at ₹80,000, 5% commission:

| | from_winner (default) | from_dividend |
|---|---|---|
| Discount = 1,00,000 − 80,000 | 20,000 | 20,000 |
| Commission = 1,00,000 × 5% | 5,000 | 5,000 |
| Dividend pool | 20,000 | 20,000 − 5,000 = 15,000 |
| Dividend per member | 20,000 ÷ 20 = 1,000 | 15,000 ÷ 20 = 750 |
| Each member pays | 80,000 ÷ 20 = **4,000** | 5,000 − 750 = **4,250** |
| Winner receives | 80,000 − 5,000 = **75,000** | **80,000** |
| Money check | in 20 × 4,000 = 80,000 = out 75,000 + 5,000 | in 85,000 = out 80,000 + 5,000 |

The calculator produces exactly these numbers (tests in `chit_calculator_test.dart`).

---

## Verified correct (with how)

**Loans**
- ₹900 on ₹300/day → 3 ledger rows, dates day 1–3 — existing test + probe.
- Partial tops up the same day first (₹100 then ₹500 → 100, 200, 300 rows) — existing test.
- Overpaying rejected (₹30,000.01 on ₹30,000) — existing test.
- Outstanding / total paid / payments left / next due on a non-multiple total: ₹1,000 @ ₹300:
  start 1,000 / 4 left; after ₹900 → 100 / 1 left / next day 4; after ₹100 → 0 / 0 / none,
  last row `paid` — probe (only "days covered" is wrong → A9).
- Days behind: started 01-01, nothing paid, viewed 01-06 → 5 days behind; fine 5 × ₹10 = ₹50 — probe.
- Fine stored on the first row only (₹600 + ₹20 fine → fines 20, 0) — existing test.
- 0.1 + 0.2: ₹0.10 then ₹0.20 on a ₹0.30 loan → paid 0.3, outstanding 0, cleared — probe.
- Append-only: UPDATE/DELETE on `loan_payments` and DELETE on `loans` blocked by triggers —
  existing test; no `delete` on loans/payments anywhere in `lib/` (grep).
- Status: active → completed only when outstanding is 0, then archived; no going back — existing test.

**Chits**
- Split maths for both modes (table above) — tests.
- No repeat winner, one auction per month, including **concurrent** calls: 3 simultaneous
  `recordAuction` calls (same month twice + same winner) → 1 saved, 2 rejected with
  readable messages — probe.
- Contributions: created at base before the auction, pending rows re-priced after it
  (25,000 → 20,000) — test; member cap enforced; terms (value, members, %, mode) lock
  after the first auction — tests.

**Dashboard & reports** (seeded: 2 loans, ₹600 + ₹15 fine and ₹100 today, one chit auction,
one ₹45,000 contribution paid)
- Dashboard: expected ₹500 (300 + 200), collected ₹700, pending borrowers 1 (the ₹100 one),
  active loans 2, active chits 1 — matches raw SQL (`SUM(amount_paid)=700`).
- Daily: collected 700, fines 15, chit 45,000, 3 entries — raw: 700 / 15 / 3 rows / 45,000.
- Monthly: 700 / 15 / 45,000 / commission 5,000 / 3 entries — matches.
- Overall: lent 5,000, collected 700, outstanding 4,300, fines 15, commission 5,000,
  dividends 10,000, contributions 45,000 — matches raw sums.
- "Today"/"this month" use `created_at` for loan money and the paid date for contributions
  (code + probe). (Prepaid borrowers are wrong → A2.)

**Other**
- Backup → restore round-trips data; login survives (password still verifies); v1 backups
  restore with defaults; newer backups rejected; guard triggers exist and block
  UPDATE/DELETE after restore — tests + probe.
- Auth: password and PIN stored as `salt$hash` (10,000 × SHA-256), never plaintext; wrong
  password rejected; "Forgot password" deletes only `users` (loans and payments kept) — probe.
- UPI link: `upi://pay?pa=ravi%40okbank&pn=Ravi%20Kumar&am=300.00&cu=INR&tn=Shop%20loan` — test.
  "Confirm paid" returns once and each caller records exactly one payment; a double tap on
  the button can't pop a second time because Flutter ignores taps on a closing route
  (`flutter/lib/src/widgets/routes.dart:1154,1222`).
- Every SPEC screen exists and is reachable from the dashboard (Payment History, Auction
  History and Contribution Tracking are sections/tabs, as README states).
- No crash or overflow on any of the 19 screens at 360 dp, seeded or empty, with null phone
  numbers and a chit with no value (widget probe). Only overflow at 1.3× font → A6.
- Rupee rounding: every service write and every report total goes through `round2`.
