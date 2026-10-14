# Feature Report — v1.1.0: chit winners become loans, monthly loans

**Result:** done and tagged `v1.1.0`. `flutter analyze`: no issues. `flutter test`:
**110 passed, 0 failed** (77 before this feature). APK: `build/app/outputs/flutter-apk/app-release.apk`
— 51.9 MB (54,463,015 bytes).

Commits: `241ee31` migration · `4b8acc0` service · `101f5d5` UI · `c1b7aee` tests · docs/release
commit tagged `v1.1.0`.

## Files changed

| File | What changed |
|---|---|
| `lib/data/database.dart` | Schema **v3**: `migrate(old, new)` with a v2→v3 step adding `loans.repayment_type / late_interest_percent / grace_days / source_chit_auction_id` (+ unique partial index) and `chit_auctions.loan_setup_status / loan_id`. v1 tables untouched. |
| `lib/models/models.dart` | `RepaymentType`, `LoanSetupStatus`, `ChitLoanItem`; `Loan.isMonthly / installmentAmount / installmentCount / periodLabel` + new fields; `ChitAuction.loanSetupStatus / loanId`; `LoanSummary.overdueInstallments / accruedLateCharge / nextDueUnpaid / paidBySlot`; `PaymentRow.repaymentType`. |
| `lib/core/format.dart` | `addMonthsClamped` (month arithmetic clamped to the month's end). |
| `lib/services/loan_service.dart` | Generalised schedule: `slotDate / slotIndex / slotKey / slotDue` drive `computeSummary` and `recordPayment` for both types; `lateInterest`; `suggestedFine(…, unpaid:)`; `insertLoan` usable inside a transaction; monthly payments/missed only on due dates. |
| `lib/services/chit_loan_service.dart` (new) | Waiting/dismissed queue, borrower matching, remaining chit instalments, one-transaction `setUpLoan`, `dismiss` / `restore`, `sourceOf(loan)`. |
| `lib/services/report_service.dart` | Monthly loans on today's schedule (only when due/overdue, due = unpaid part); waiting count for the dashboard banner. |
| `lib/screens/loans/loan_terms_form.dart` (new) | Shared Daily/Monthly terms widget + controller. |
| `lib/screens/loans/loan_setup_screen.dart` (new) | Loan Setup for a chit winner. |
| `lib/screens/loans/loan_form_screen.dart` | Uses the shared terms widget (Daily/Monthly). |
| `lib/screens/loans/loan_list_screen.dart` | "Waiting for setup" section, Waiting/Dismissed filter, Not a loan, Restore, "₹X / day|month". |
| `lib/screens/loans/loan_details_screen.dart` | Monthly labels, accrued late interest, overdue instalments, "From chit" link, monthly-aware Mark missed. |
| `lib/screens/loans/payment_entry_screen.dart` | Monthly instalment picker, "Late interest" pre-fill with formula helper. |
| `lib/screens/loans/payment_history_tile.dart`, `borrowers/borrower_profile_screen.dart`, `reports/reports_screen.dart` | "Late interest" vs "Fine"; "/month" vs "/day". |
| `lib/screens/dashboard/dashboard_screen.dart` | "N chit winners need loan setup" banner; monthly overdue wording. |
| `lib/screens/chits/chit_details_screen.dart` | Auction history: Waiting / Loan created / Dismissed chip, tap → setup or loan. |
| 8 screens' `_reload()` | `setState` closure no longer returns a Future (debug assertion; see Decisions 14). |
| `lib/screens/settings/settings_screen.dart`, `pubspec.yaml` | Version 1.1.0 (+2). |
| `test/monthly_loan_test.dart`, `test/chit_loan_setup_test.dart`, `test/chit_loan_ui_test.dart` (new); `test/migration_test.dart`, `test/screens_360_test.dart`, `test/dashboard_test.dart` | New tests (below). |
| `SPEC.md`, `README.md`, `CHANGELOG.md`, `FEATURE_REPORT.md` | Docs. |

## Formulas

- **Instalment due date** `slotDate(i)` (i = 0, 1, 2 …):
  - daily: `start + i days`
  - monthly: `start + i months`, day = `min(start day, last day of that month)`, always from
    the start date (31 Jan → 28/29 Feb → 31 Mar → 30 Apr — never "28 Feb + 1 month = 28 Mar").
- **Amount due on instalment i** = `min(instalment, total − instalment × i)` (smaller last one).
- **Payments left** = ⌈outstanding ÷ instalment⌉. **Days behind** = today − next due date.
  **Overdue instalments** = instalments due before today that aren't fully paid.
- **Daily fine** = late days × fine per day.
- **Monthly late interest** = `round2(unpaid part of that instalment × rate% / 100 × max(0, days late − grace days) / 30)`
  — simple interest on the overdue instalment only, never on the whole loan, never compounding.
  ₹5,000 at 2 %, 45 days late → **150.00**; with 15 grace days → **100.00**; on time → **0**.
- **Accrued late interest** (Loan Details) = the same formula summed over all overdue
  instalments as of today (info only; charged when the payment is recorded).
- **Dashboard due (monthly)** = unpaid part of the next due instalment + money collected today
  (capped by outstanding); listed only when that instalment is due today or overdue.
- **Prize** = `winner_payout`, or `winning_amount` for auctions without a payout.
- **Remaining chit instalments** (info) = months from the auction month to the chit's end −
  that member's contributions already marked paid in those months.

## Test results

`flutter test`: **110 passed, 0 failed.** New coverage:
- Setup queue: one pending item per saved auction (and dashboard count); setup creates one
  linked loan; a second setup is rejected; **two setups started together → exactly one loan,
  one borrower**; a failed setup rolls back the new borrower; borrower matching (phone, name,
  no match); dismiss / restore and their invalid transitions; remaining chit instalments;
  loan → chit link; no-repeat-winner and one-auction-per-month still hold.
- Monthly: 31 Jan → 28 Feb / 29 Feb (2028) → 31 Mar → 30 Apr; 3 instalments at once = 3 rows;
  partial top-up; overpay rejected; append-only + status rules; late interest 150.00 / 100.00
  / 0; interest only on the unpaid part; accrued interest over two overdue instalments (300.00);
  fine stored on the first row only; only due dates accepted.
- Daily loan created after the migration behaves exactly as before (all 77 earlier tests also pass).
- Dashboard: monthly loan hidden before due, shown when due (expected = unpaid part), collected
  after paying, overdue instalment shown.
- Migration: a real **v2 database** with a daily loan + payment and an auction opens on v3 —
  loan is `daily` with unchanged numbers, auction is `pending`, triggers still work;
  fresh and upgraded schemas have identical columns.
- Backups: round-trip with a monthly chit-sourced loan (terms, link, payment, fine); a v2
  backup restores with daily loans and pending auctions.
- UI: dashboard banner; waiting item → Loan Setup (prize pre-filled, months → instalment
  suggested) → loan created, opened, "From chit" and "₹25,000.00 / month" shown; Not a loan →
  Dismissed → Restore; new screens at 360 dp with 1.3× font.

## Decisions I made

1. **Schema v2 → v3.** The app was already on v2 (commission modes), so "bump by 1" = v3.
2. **One loan per auction is enforced twice:** the setup transaction only updates an auction
   that is still `pending`, and a unique partial index on `loans.source_chit_auction_id`.
3. **`source_chit_auction_id` has no foreign key** — restore inserts loans before chit
   tables, so an FK there would break restoring backups. `chit_auctions.loan_id` does have one.
4. **Loan Setup defaults to Monthly** (chit prizes are usually repaid monthly); the normal
   New loan form still defaults to Daily. "Number of months" starts empty (it is asked).
5. **Monthly payments and "missed" marks only on instalment due dates.** Payment Entry shows
   an instalment picker instead of a date picker; the service rejects other dates.
6. **Late days count from the due date to the day the payment is entered**; the interest is on
   the unpaid part of the chosen instalment.
7. **"Overdue in instalments plus days"** = number of overdue instalments and days since the
   earliest unpaid due date ("2 instalments overdue · 45 days late").
8. **Borrower matching** ignores archived borrowers (they can't take loans); phone must match
   exactly (trimmed); name matching (case-insensitive) is used only when the member has no phone.
9. **Remaining chit instalments** = months left from the auction month minus contributions
   already marked paid (info only).
10. Only **pending** items can be dismissed and only **dismissed** ones restored; a created
    loan can't be dismissed.
11. For monthly loans `fine_per_day` is stored as 0; for daily loans late interest and grace
    days are stored as 0. Late interest is limited to 0–100 % a month.
12. After setup the app **opens the new loan**; the waiting section shows on every status tab.
13. Default loan name: "<chit> — month N prize" (editable).
14. **Fixed a latent bug** found by the new UI tests: `_reload()` in 8 screens used
    `setState(() => _future = …)`, whose callback returns a Future — Flutter's debug-mode
    assertion rejects that (in debug builds the dashboard's quick payment showed "Something
    went wrong" after saving). Release builds strip asserts, so phones were not affected.
    The A1 dashboard test now also checks that no error appears.
15. Three migration-test assertions that hard-coded schema **2** now use
    `AppDatabase.schemaVersion` (same strictness, follows the schema).

## 5-minute phone test

Install the APK over v1.0.0 (your data is kept and upgraded). Dates below are relative to today.

1. **Record an auction (1 min).** Today → *Chits* → *New chit*: "Test chit", value `100000`,
   members `2`, months `2`, commission `5`, paid by *Winner* → *Create chit*. Open it → *Add member*
   "Anu" phone `9000000001`, then "Bala" → *Auctions* → *Record auction*: month 1, winner Anu,
   winning amount `80000` → *Save auction*. ✔ The auction shows a **Waiting** chip.
2. **Waiting item (½ min).** Back to **Today**: ✔ banner "1 chit winner needs loan setup" → tap
   it → Loans: ✔ "Waiting for setup (1)" with Anu · Test chit · month 1 · Prize ₹75,000.00.
3. **Set up a monthly loan (1½ min).** Tap Anu → *Loan setup*: ✔ Monthly is selected, Total payable
   75000.00, Borrower "New borrower: Anu (9000000001)", remaining chit instalments 2.
   Number of months `3` → ✔ Monthly instalment fills in 25000.00. First due date → pick the date
   **20 days ago**. Late interest `2`, Grace days `0` → *Create loan*.
   ✔ The loan opens: "₹25,000.00 / month", "From chit: Test chit, month 1",
   "1 instalment overdue · 20 days late", **Late interest due so far ₹333.33**
   (25,000 × 2 % × 20 ÷ 30).
4. **Pay late (1 min).** *Record payment*: ✔ amount ₹25,000.00, "Instalment 1 · due <20 days ago>",
   **Late interest ₹333.33** pre-filled (helper shows the formula) → *Save payment*.
   ✔ Outstanding ₹50,000.00, the overdue line is gone, history shows the row with
   "Late interest ₹333.33", next due is about 10 days from now.
5. **Check the links (1 min).** Back to **Today**: ✔ no banner; Anu's loan shows as
   **Collected** today (tomorrow it drops off the schedule until the next instalment is due). Chits → Test chit → *Auctions*: ✔ month 1 shows
   **Loan created**; tap it → opens the loan.
6. *(Optional)* Record month 2's auction for Bala → Loans → tap ✕ on Bala → *Not a loan* →
   ✔ "Dismissed (1)" → tap it → *Restore* → Bala is waiting again.
