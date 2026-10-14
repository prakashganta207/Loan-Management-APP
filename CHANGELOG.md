# Changelog

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
