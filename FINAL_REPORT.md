# Final Report — Loan & Chit Manager v1.0.0

**Result:** released as v1.0.0 (git tag `v1.0.0`). `flutter analyze`: **no issues**
(0 errors, 0 warnings). `flutter test`: **77 passed, 0 failed** (36 before the audit).

- **APK:** `build/app/outputs/flutter-apk/app-release.apk` — 51.7 MB (54,184,255 bytes)
- Full findings with proof: `AUDIT.md`. Release notes: `CHANGELOG.md`.

## Checklist

| # | Item | Result | How it was verified |
|---|---|---|---|
| **Loans** ||||
| 1 | ₹900 on ₹300/day → 3 rows; partial tops up the same day; overpaying rejected | **PASS** | tests `loan_service_test.dart` |
| 2 | Outstanding, total paid, fines, next due, days behind, payments left — incl. last day when the total isn't a multiple | **PASS** (after A9) | ₹1,000 @ ₹300: 1,000/4 left → 100/1 left/next day 4 → 0/0/none, 4 of 4 covered; 5 days behind, ₹50 fine — tests |
| 3 | `loan_payments` append-only (triggers); loans never deleted | **PASS** | trigger test; no delete of loans/payments in `lib/` |
| 4 | Status active → completed (outstanding 0) → archived only | **PASS** | test |
| 5 | Fine = late days × fine/day, stored on the first row only | **PASS** | tests |
| — | Dashboard quick "Mark paid" records exactly one payment on a double tap | **PASS** (after A1) | widget test `dashboard_test.dart` |
| **Chits** ||||
| 6 | ₹1,00,000 / 20 members / ₹80,000 / 5%: discount 20,000, commission 5,000; winner-pays: dividend 1,000, each pays 4,000, winner gets 75,000; members-pay: dividend 750, each pays 4,250, winner gets 80,000 | **PASS** | worked by hand in AUDIT.md + calculator tests |
| 7 | No member wins twice; one auction per month, even with a double tap | **PASS** | tests + 3 concurrent `recordAuction` calls → 1 saved |
| 8 | Contributions created with the right amount; rows created before the auction re-priced after it | **PASS** for pending rows; rows already ticked paid keep the old amount → **A7, owner decision** | tests |
| 9 | Member count ≤ chit size; terms lock after the first auction | **PASS** | tests |
| — | Chit rule "members pay auctioned price ÷ members" | **PASS** — implemented as the default per-chit mode, with migration and lock | tests |
| **Dashboard & reports** ||||
| 10 | Today / this month use `created_at`; expected vs collected; pending borrowers | **PASS** (after A2) | `report_service_test.dart` |
| 11 | Daily, monthly and overall reports match the raw database | **PASS** | seeded probe: every figure equals the raw SQL sum (AUDIT.md) |
| **Other** ||||
| 12 | Backup → restore round-trip; login kept; old backups restore; guard triggers recreated | **PASS** | `migration_test.dart` + probe |
| 13 | Password and PIN hashed; wrong password rejected; forgot password keeps business data | **PASS** | probe (salt$hash stored; 1 loan + 1 payment kept after reset) |
| 14 | UPI link encoded correctly; "Confirm paid" records exactly one payment | **PASS** | test; single call path + Flutter ignores taps on a closing dialog |
| 15 | Every SPEC screen exists and is reachable; no crash on empty lists, null phones, chit with no value | **PASS** | `screens_360_test.dart` (19 screens, seeded + empty) |
| 16 | No overflow at 360 dp; async actions guarded with `mounted`; readable errors | **PASS** (after A6, A4, A5) | 360 dp test at 1.3× font; widget test for A4; tests for A5 |
| 17 | Rupee rounding through `round2`, no 0.1 + 0.2 leftovers | **PASS** | ₹0.10 + ₹0.20 → paid 0.3, outstanding 0 |

## Findings fixed

| Finding | Severity | Fix | Commit |
|---|---|---|---|
| A1 Double tap on "Mark paid" recorded twice | CRITICAL | per-loan in-flight guard, buttons disabled while saving | `220617b` |
| A2 Paid-ahead borrowers shown as due/pending | HIGH | skip loans whose next due is after today when nothing was collected today | `362e1da` |
| A4 `setState` after the screen closed | MEDIUM | `mounted` checks in login, settings, auction entry, chit details, splash | `1a0f188` |
| A5 Programmer error text; damaged backup messages | MEDIUM | plain message + details line; restore wraps failures in one clear message | `ef6b1c9` |
| A6 Borrower profile tile overflow at 1.3× font | MEDIUM | trailing column scales down | `9a43e44` |
| A9 "3 of 4 days covered" on a fully paid loan | LOW | last day's due = what is left of the total | `99d5d95` |
| A10 Payments before the loan start accepted | LOW | service rejects them | `ba9ac93` |
| A11 Dashboard row opened details, SPEC says payment entry | LOW | tap → payment entry, long-press → details | `9c360e8` |
| A12 UPI buttons shown without a UPI ID | LOW | shown only when configured | `2d2c6ad` |

## Needs owner decision (not implemented)

| Finding | Severity | My recommendation |
|---|---|---|
| A3 No way to reverse a wrong payment | HIGH | **Do this first.** Add an append-only *reversal* entry (negative amount, required note, linked to the original row) with a schema v3 migration, and amend SPEC rule 4. Until then, check the amount before saving. |
| A7 Contribution ticked paid before the auction keeps the pre-auction amount | MEDIUM | Block "mark paid" for a month until its auction is recorded. |
| A8 With "apply extra" off, the schedule doesn't move forward | MEDIUM | Keep (the switch explains it), or remove the switch. |
| A13 UPI confirm may store `partial` (SPEC said `paid`) | LOW | Keep; SPEC now describes it. |
| A14 Chit duration not tied to member count | LOW | Warn when they differ. |
| A15 A fine can't be collected on its own | LOW | Allow a fine-only entry. |
| A16 "Total lent" is total payable (incl. interest) | LOW | Keep the label; add a principal field only if you want profit reports. |

## Unresolved
None.

## 10-minute phone test

Install `app-release.apk` (allow "install unknown apps" when asked). Use a fresh install, or
export a backup first.

1. **First run (1 min).** Open the app → "Set up your account": name, password `test123`
   (twice), PIN `1234` → *Create account* → you land on **Today**.
2. **Lock & unlock (1 min).** Settings → *Lock app now* → enter PIN `1234` → Today. Lock
   again → *Use password instead* → type `wrong12` → "Wrong password" → type `test123` → Today.
3. **Loan & split (2 min).** Today → *Borrowers* → *Add borrower* "Ravi" (leave phone empty)
   → back → *Loans* → *New loan*: Ravi, "Shop loan", total `1000`, daily `300` (duration fills
   to 4), fine `10`, start today → *Create loan*. Open it → *Record payment* → amount `900` →
   the "Apply the extra to following days" switch is on → *Save payment*.
   ✔ Message says "3 ledger entries"; Outstanding ₹100.00; Days covered 3 of 4; Next due is
   3 days from today; history shows 3 rows.
4. **Paid ahead (½ min).** Back to **Today**: Ravi shows *Collected* (₹900 today).
5. **Last smaller instalment (1 min).** Open the loan → *Record payment* → amount is ₹100.00
   → *Save*. ✔ Outstanding ₹0.00, Days covered 4 of 4, *Mark completed* appears → tap it →
   *Archive loan* appears.
6. **Double-tap guard (1 min).** Add a second loan for a new borrower "Sita": total `3000`,
   daily `300`, start today. On **Today**, tap Sita's ✓ twice quickly.
   ✔ Only ₹300 is recorded (open the loan: 1 history row).
7. **Overpay blocked (½ min).** Sita's loan → *Record payment* → amount `5000` → *Save*.
   ✔ "Amount is more than the outstanding balance (₹2,700.00)".
8. **Chit (2 min).** Today → *Chits* → *New chit*: "Test chit", value `100000`, members `4`,
   months `4`, commission `5`, "Commission paid by" = *Winner* → *Create chit*. Open it →
   *Add member* ×4 (A, B, C, D) → *Auctions* → *Record auction*: month 1, winner A, winning
   amount `80000`. ✔ Preview: Winner receives ₹75,000.00; Each member pays ₹20,000.00
   (₹80,000.00 ÷ 4). Save → *Contributions* (month 1) already lists 4 rows at ₹20,000.00 —
   tick one as paid. *Auctions* → *Record auction* again → A is not in the winner list.
9. **Calculator (½ min).** Today → *Chit calculator*: 100000, 20, 80000, 5 → *Winner*: each
   pays ₹4,000.00, winner ₹75,000.00; switch to *Members*: ₹4,250.00 and ₹80,000.00.
10. **Reports (½ min).** Today → *Reports* → Daily shows ₹1,300.00 loan collections
    (900 + 100 + 300).
11. **UPI (½ min).** Sita's loan shows no "Pay via UPI" button. Settings → *UPI ID*
    `yourname@okbank` → back to the loan → *Pay via UPI* appears → it opens your UPI app with
    the amount filled in → come back → *Not yet* records nothing.
12. **Backup (1 min).** Settings → *Export backup now* → note the path. *Restore from
    backup* → pick that file → confirm twice. ✔ "Backup restored", you're on Today with the
    same numbers and still logged in.
    ⚠ Not verifiable without a phone: on Android 11+ some file pickers hide the
    `Android/data/…/files/backups` folder. If you can't see the file, copy it to Downloads
    with a computer (USB) and pick it from there — and tell me, because then the backup
    folder should move.
