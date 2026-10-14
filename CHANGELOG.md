# Changelog

## v1.1.0 — 2026-10-15

### New: chit winners become loans
- When an auction is saved, the winner appears in **Loans → Waiting for setup** (name, chit,
  month, prize) and the dashboard shows "N chit winners need loan setup". Auctions recorded
  before this version appear there too.
- **Loan Setup** screen: repayment type first (Daily or Monthly), total payable pre-filled
  with the prize, borrower matched by phone (or name) or created from the chit member, and
  the member's remaining chit instalments shown for reference.
- "Not a loan" dismisses an item (with confirmation); the Dismissed filter restores it.
- Loan Details shows "From chit: <name>, month N"; the chit's auction history shows
  Waiting / Loan created / Dismissed and links to the loan.

### New: monthly loans
- The New loan form and Loan Setup share a Daily/Monthly choice. Monthly: number of months,
  monthly instalment (suggested as total ÷ months), first due date, late interest % per
  month and grace days.
- Due dates step one month at a time from the first due date, clamped to the month's end
  (31 Jan → 28/29 Feb → 31 Mar → 30 Apr).
- Everything that worked for daily loans works for monthly ones: paying several
  instalments at once (one ledger row each), partial top-ups, no overpaying, append-only
  ledger, active → completed → archived, next due date, overdue count, reports.
- Late interest = unpaid instalment × rate % × (days late − grace days) ÷ 30, simple
  interest on the overdue instalment only. Pre-filled on payment entry; accrued interest is
  shown on Loan Details.
- The dashboard lists a monthly loan only when an instalment is due today or overdue.
- Every screen shows "₹X / day" or "₹X / month" as appropriate.

### Database
- Schema v3 (migration from v2; history untouched). Backups from v1, v2 and v3 restore.

### Fixed
- Several screens refreshed with a `setState` callback that returned a Future, which trips
  a Flutter debug assertion (debug builds showed "Something went wrong" after a quick
  payment on the dashboard). Release builds were not affected.

## v1.0.0 — 2026-10-14

First release. An offline Android app for a small lender; all data stays on the phone.

### What's in the app
- **Borrowers:** add, edit, search, archive; profile with loans, payment history, fines and
  outstanding balance.
- **Daily-collection loans:** total payable, daily amount, duration, fine per late day, start
  date. Append-only payment ledger (database triggers block edits and deletes). Multi-day
  split (₹900 on ₹300/day → 3 rows), partial top-ups, a smaller last instalment, missed
  days, late fines, no overpaying, status active → completed → archived.
- **Today's dashboard:** expected vs collected, pending borrowers, quick paid/missed buttons,
  backup reminder.
- **Chit funds:** members, auctions (no repeat winners, one auction per month, enforced in a
  transaction), contributions per month, terms that lock after the first auction.
  Commission mode per chit: *winner pays* (default — members pay auctioned price ÷ members,
  commission deducted from the winner's prize) or *members pay* (commission deducted from
  the dividend).
- **Chit calculator** with both commission modes and the payment formula.
- **Reports:** daily, monthly and overall.
- **Security:** local password (salted, iterated SHA-256), optional PIN and fingerprint;
  "Forgot password" resets the login only.
- **Backup/restore:** JSON export; restore is all-or-nothing, keeps the login and accepts
  older backups.
- **UPI:** opens the lender's UPI app with the amount filled in, then asks to confirm.
- Database schema v2 with a migration from v1.

### Fixed by the pre-release audit (see AUDIT.md)
- **A1 (critical):** a double tap on the dashboard's "Mark paid" recorded the payment twice.
- **A2:** borrowers who had paid ahead showed as due and pending, which inflated "expected".
- **A4:** several screens could crash if closed while saving (missing `mounted` checks).
- **A5:** damaged backups and unexpected errors showed programmer messages; a damaged backup
  now says so plainly and changes nothing.
- **A6:** the borrower profile's loan tiles overflowed with a larger phone font.
- **A9:** a fully paid loan with a smaller last instalment showed "3 of 4 days covered".
- **A10:** the service accepted payments and missed days dated before the loan started.
- **A11:** dashboard rows now open Payment Entry as the spec says (long-press for details).
- **A12:** UPI buttons now appear only after a UPI ID is set.

### Known, waiting for the owner's decision
A3 (no way to reverse a wrong payment), A7 (contribution ticked before the auction keeps the
old amount), A8, A13–A16 — see "Needs owner decision" in AUDIT.md.
