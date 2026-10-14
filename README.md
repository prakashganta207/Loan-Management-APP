# Loan & Chit Manager (v1.1.0)

Offline Flutter app for a small lender: daily and monthly loans with an auditable
ledger, chit funds with auctions and contributions (each auction winner can become a
loan in one step), reports, local backup and a UPI deep-link payment trigger. Built against the frozen spec in `SPEC.md`.

## Setup (on your machine)

```bash
cd loan_chit_manager
flutter create . --project-name loan_chit_manager --platforms android,ios
dart run tool/setup_android.dart     # UPI <queries> + fingerprint fixes, see below
flutter pub get
flutter analyze
flutter test
flutter run
```

`flutter create .` only adds the missing platform folders; it does not overwrite `lib/`.

### What `tool/setup_android.dart` changes (do it by hand if you prefer)

1. **UPI on Android 11+** — without this, `Pay via UPI` silently says "No UPI app found".
   In `android/app/src/main/AndroidManifest.xml`, inside `<queries>`:
   ```xml
   <intent>
       <action android:name="android.intent.action.VIEW"/>
       <data android:scheme="upi"/>
   </intent>
   ```
2. **Fingerprint unlock** — `local_auth` needs `FlutterFragmentActivity`, otherwise the
   prompt never appears. In `MainActivity.kt`:
   ```kotlin
   import io.flutter.embedding.android.FlutterFragmentActivity
   class MainActivity : FlutterFragmentActivity()
   ```
   and add `<uses-permission android:name="android.permission.USE_BIOMETRIC"/>` to the manifest.

If the Android build complains about `minSdk`, set `minSdk = 23` in
`android/app/build.gradle(.kts)`.

## Verification checklist

- [ ] `flutter analyze` — no issues
- [ ] `flutter test` — calculator, loan ledger, chit rules, migrations, backup round-trip,
      dashboard/report numbers and every screen at 360 dp (runs on desktop via
      `sqflite_common_ffi`, no emulator needed)
- [ ] First run: create account → dashboard
- [ ] Add borrower → add loan (₹30,000 total, ₹300/day) → record ₹900 → history shows 3 rows
- [ ] Dashboard: tick "paid" and "missed" on today's schedule
- [ ] Create chit, add members, record an auction → the winner disappears from the next auction's list
- [ ] The winner appears in Loans → "Waiting for setup" (and a banner on Today) → set up a
      monthly loan → it shows "₹X / month" and "From chit: …"
- [ ] Settings → set UPI ID → Loan → Pay via UPI opens your UPI app
- [ ] Settings → Export backup → Restore it

## Project layout

```
lib/
  core/        formatting, dates, theme, routes, ValidationException
  data/        database.dart — schema v3 (+ v1→v2→v3 migrations), indexes, append-only ledger triggers
  models/      plain data classes for every table
  services/    all business rules (screens never write SQL)
    loan_service.dart      ledger, daily/monthly schedule, multi-instalment split, fines,
                           late interest, status transitions
    chit_loan_service.dart chit winners waiting for loan setup (one-transaction setup)
    chit_service.dart      members, auctions (transactional no-repeat-winner), contributions
    chit_calculator.dart   the single source of chit maths
    report_service.dart    dashboard, daily / monthly / overall reports
    auth_service.dart      salted, iterated SHA-256 password + PIN
    backup_service.dart    JSON export / atomic restore
    upi_service.dart       upi://pay link building + launch
  widgets/     shared UI pieces
  screens/     auth, dashboard, borrowers, loans, chits, calculator, reports, settings
test/          unit tests against an in-memory database
tool/          setup_android.dart
```

## Rules enforced below the UI

- **Ledger is append-only.** SQLite triggers block UPDATE/DELETE on `loan_payments`
  and DELETE on `loans`. There is no correction entry yet, so a saved payment cannot be
  reversed (AUDIT A3 — needs owner decision).
- **Multi-day payments.** ₹900 on a ₹300/day loan becomes three rows, one per schedule day.
  A partial payment tops up the same day first. The lender can turn the split off per payment
  (then the money is one row and the schedule does not move past that day).
- **Smaller last instalment.** Day *i* is due `min(daily, total − daily × i)`, so ₹1,000 at
  ₹300/day is 300, 300, 300, 100 and the loan shows 4 of 4 days covered when cleared.
- **No overpaying, no early dates.** A payment larger than the outstanding balance, or dated
  before the loan's start date, is rejected. All money is rounded to paise (`round2`).
- **Fines** go on the first ledger row of a payment: late days × fine per day, editable.
- **Monthly loans** use the same schedule and ledger rules with one instalment per month:
  instalment *i* is due on start + *i* months, clamped to the month's end and always counted
  from the start date (31 Jan → 28/29 Feb → 31 Mar → 30 Apr). Paying 3 months at once makes
  3 ledger rows. `daily_payment` / `duration_days` hold the monthly instalment / number of
  months (read through `Loan.installmentAmount` / `installmentCount`).
- **Late interest (monthly)** = unpaid part of the overdue instalment × rate % ÷ 100 ×
  max(0, days late − grace days) ÷ 30, rounded to paise. Simple interest on that instalment
  only — never on the whole loan, never compounding. Pre-filled and editable, stored as the
  payment's fine, and shown as "late interest due so far" on Loan Details.
- **Loan status** only moves active → completed (when outstanding is zero) → archived.
- **No repeat chit winners.** Checked and set inside one transaction, plus a unique
  `(chit, month)` constraint on auctions.
- **"Today's collection"** is keyed on when money was recorded (`created_at`), not the
  schedule day it covers, so borrowers who are behind still show up correctly. Borrowers who
  paid ahead on an earlier day are not listed as due or pending. The quick ✓/✗ buttons ignore
  a double tap.
- **Two chit commission modes** (chosen per chit, `ChitCalculator` is the only place the maths lives):
  - *Winner pays* (`from_winner`, default for new chits): the whole discount is shared, each
    member pays winning amount ÷ members, and the winner receives winning amount − commission.
  - *Members pay* (`from_dividend`): commission comes out of the discount first, each member
    pays chit value ÷ members − dividend, and the winner receives the full winning amount.
  Chits created before schema v2 stay on `from_dividend` so recorded auctions remain correct.
- **Chit terms lock** (value, members, commission %, commission mode) after the first auction.
- **Chit winner → loan.** Every saved auction becomes a "Waiting for setup" item (auctions
  from before v1.1.0 too). Setting up the loan and marking the auction "Loan created" happen
  in one transaction, and the database allows only one loan per auction, so a double tap
  can't create two loans. "Not a loan" dismisses an item; it can be restored.
- **Contributions** start at chit value ÷ members; recording the month's auction re-prices the
  rows still pending to the calculator's "each member pays" amount.
- **Restore is all-or-nothing.** It runs in one transaction, keeps the login, re-creates the
  ledger triggers, accepts v1/v2 backups, rejects newer ones, and a damaged file changes nothing.

## Deliberate simplifications

- Payment history and auction history are sections inside Loan Details and Chit
  Details rather than separate screens.
- Dashboard rows open Payment Entry; long-press a row for the full Loan Details.
- UPI buttons appear only after a UPI ID is set in Settings.
- Missed days add a zero-amount "missed" row; fines are charged when the late
  payment is recorded (late days × fine per day, editable).
- Backups are written to the app's external files folder
  (`Android/data/<package>/files/backups`) — copy them off the phone yourself.
- UPI confirmation is manual; there is no payment verification (per spec).
