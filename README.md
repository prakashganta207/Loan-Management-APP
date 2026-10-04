# Loan & Chit Manager (V1)

Offline Flutter app for a small lender: daily-collection loans with an auditable
ledger, chit funds with auctions and contributions, reports, local backup and a
UPI deep-link payment trigger. Built against the frozen spec in `SPEC.md`.

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

- [ ] `flutter analyze` — no errors
- [ ] `flutter test` — calculator, loan ledger, chit rules, backup round-trip (runs on
      desktop via `sqflite_common_ffi`, no emulator needed)
- [ ] First run: create account → dashboard
- [ ] Add borrower → add loan (₹30,000 total, ₹300/day) → record ₹900 → history shows 3 rows
- [ ] Dashboard: tick "paid" and "missed" on today's schedule
- [ ] Create chit, add members, record an auction → the winner disappears from the next auction's list
- [ ] Settings → set UPI ID → Loan → Pay via UPI opens your UPI app
- [ ] Settings → Export backup → Restore it

## Project layout

```
lib/
  core/        formatting, dates, theme, routes, ValidationException
  data/        database.dart — schema v1, indexes, append-only ledger triggers
  models/      plain data classes for every table
  services/    all business rules (screens never write SQL)
    loan_service.dart      ledger, multi-day split, fines, status transitions
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
  and DELETE on `loans`. Corrections are new rows with a note.
- **Multi-day payments.** ₹900 on a ₹300/day loan becomes three rows, one per schedule day.
  A partial payment tops up the same day first. The lender can turn the split off per payment.
- **No overpaying.** A payment larger than the outstanding balance is rejected.
- **Loan status** only moves active → completed (when outstanding is zero) → archived.
- **No repeat chit winners.** Checked and set inside one transaction, plus a unique
  `(chit, month)` constraint on auctions.
- **"Today's collection"** is keyed on when money was recorded (`created_at`), not the
  schedule day it covers, so borrowers who are behind still show up correctly.
- **Chit terms lock** (value, members, commission) after the first auction.

## Deliberate simplifications

- Payment history and auction history are sections inside Loan Details and Chit
  Details rather than separate screens.
- Missed days add a zero-amount "missed" row; fines are charged when the late
  payment is recorded (late days × fine per day, editable).
- Backups are written to the app's external files folder
  (`Android/data/<package>/files/backups`) — copy them off the phone yourself.
- UPI confirmation is manual; there is no payment verification (per spec).
