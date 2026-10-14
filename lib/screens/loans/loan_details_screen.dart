import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/chit_loan_service.dart';
import '../../services/loan_service.dart';
import '../../services/upi_service.dart';
import '../../widgets/common.dart';
import '../chits/chit_details_screen.dart';
import 'payment_entry_screen.dart';
import 'payment_history_tile.dart';

class _LoanData {
  const _LoanData(this.summary, this.payments, this.upiReady, this.source);
  final LoanSummary summary;
  final List<LoanPayment> payments;
  final bool upiReady;

  /// The chit auction this loan was set up for, if any.
  final ChitLoanItem? source;
}

class LoanDetailsScreen extends StatefulWidget {
  const LoanDetailsScreen({super.key, required this.loanId});
  final int loanId;

  @override
  State<LoanDetailsScreen> createState() => _LoanDetailsScreenState();
}

class _LoanDetailsScreenState extends State<LoanDetailsScreen> {
  final _service = LoanService();
  late Future<_LoanData> _future = _load();

  Future<_LoanData> _load() async {
    final payments = await _service.payments(widget.loanId);
    final summary = await _service.summary(widget.loanId);
    return _LoanData(
      summary,
      payments.reversed.toList(),
      (await UpiService().config()) != null,
      await ChitLoanService().sourceOf(summary.loan),
    );
  }

  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _recordPayment() async {
    final saved = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => PaymentEntryScreen(loanId: widget.loanId)));
    if (saved == true && mounted) _reload();
  }

  Future<void> _markMissed(LoanSummary s) async {
    final today = todayKey();
    final next = s.nextDueDate;
    if (s.loan.isMonthly && (next == null || next.compareTo(today) > 0)) {
      showMessage(context, 'The next instalment is not due yet');
      return;
    }
    final slot = (next != null && next.compareTo(today) <= 0) ? next : today;
    final ok = await confirmAction(context,
        title: 'Mark as missed?',
        message: 'Adds a "missed" entry for ${prettyDate(slot)}. Nothing is charged now; '
            'the ${s.loan.isMonthly ? 'late interest' : 'fine'} is added when the borrower '
            'pays late.',
        confirmLabel: 'Mark missed');
    if (!ok) return;
    try {
      await _service.markMissed(loanId: widget.loanId, slotDate: slot);
      if (mounted) _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _upi(LoanSummary s) async {
    final suggested = s.loan.isMonthly
        ? s.nextDueUnpaid
        : round2(math.min(s.loan.installmentAmount, s.outstanding));
    final text = await promptText(context,
        title: 'Amount to collect by UPI',
        label: 'Amount (₹)',
        initial: suggested.toStringAsFixed(2),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        confirmLabel: 'Open UPI app');
    if (text == null || !mounted) return;
    final amount = parseAmount(text);
    if (amount == null || amount <= 0) {
      showMessage(context, 'Enter a valid amount', error: true);
      return;
    }
    if (amount > s.outstanding + kEps) {
      showMessage(context, 'Amount is more than the outstanding ${money(s.outstanding)}',
          error: true);
      return;
    }
    final confirmed = await runUpiFlow(context, amount: amount, note: s.loan.loanName);
    if (!confirmed || !mounted) return;
    try {
      await _service.recordPayment(
        loanId: widget.loanId,
        slotDate: s.nextDueDate ?? todayKey(),
        amount: amount,
        note: 'UPI',
      );
      if (!mounted) return;
      showMessage(context, 'UPI payment of ${money(amount)} recorded');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _openChit(int chitId) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => ChitDetailsScreen(chitId: chitId)));
    if (mounted) _reload();
  }

  Future<void> _changeStatus(String status) async {
    final ok = await confirmAction(context,
        title: status == RecordStatus.completed ? 'Mark loan completed?' : 'Archive this loan?',
        message: status == RecordStatus.completed
            ? 'The balance is fully paid. Completed loans stop appearing in today\'s schedule.'
            : 'Archived loans are kept for records but hidden from the main lists.',
        confirmLabel: status == RecordStatus.completed ? 'Mark completed' : 'Archive');
    if (!ok) return;
    try {
      await _service.updateStatus(widget.loanId, status);
      if (mounted) _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<_LoanData>(
      future: _future,
      standalone: true,
      builder: (context, d) {
        final s = d.summary;
        final loan = s.loan;
        final active = loan.status == RecordStatus.active;
        return Scaffold(
          appBar: AppBar(title: Text('${loan.borrowerName} — ${loan.loanName}')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                        child: Text('Outstanding',
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      StatusChip(loan.status),
                    ]),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        money(s.outstanding),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: s.isCleared ? AppColors.paid : AppColors.missed,
                            ),
                      ),
                    ),
                    if (s.overdueDays > 0)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                            loan.isMonthly
                                ? '${s.overdueInstallments} instalment'
                                    '${s.overdueInstallments == 1 ? '' : 's'} overdue · '
                                    '${s.overdueDays} day${s.overdueDays == 1 ? '' : 's'} late'
                                : '${s.overdueDays} day${s.overdueDays == 1 ? '' : 's'} behind schedule',
                            style: const TextStyle(color: AppColors.missed, fontWeight: FontWeight.w600)),
                      ),
                    if (d.source != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          onPressed: () => _openChit(d.source!.chitId),
                          icon: const Icon(Icons.groups, size: 18),
                          label: Text('From chit: ${d.source!.chitName}, '
                              'month ${d.source!.monthNumber}'),
                        ),
                      ),
                    const Divider(height: 24),
                    InfoRow('Total payable', money(loan.totalPayable)),
                    InfoRow('Paid so far', money(s.totalPaid)),
                    if (loan.isMonthly) ...[
                      InfoRow('Late interest collected', money(s.totalFine)),
                      if (s.accruedLateCharge > 0)
                        InfoRow('Late interest due so far', money(s.accruedLateCharge),
                            color: AppColors.missed),
                      InfoRow('Monthly instalment', '${money(loan.installmentAmount)} / month'),
                      InfoRow('Late interest',
                          '${loan.lateInterestPercent}% a month after ${loan.graceDays} grace days'),
                      InfoRow('First due', prettyDate(loan.startDate)),
                      InfoRow('Instalments paid',
                          '${s.coveredDays} of ${loan.installmentCount}'),
                    ] else ...[
                      InfoRow('Fines collected', money(s.totalFine)),
                      InfoRow('Daily payment', '${money(loan.installmentAmount)} / day'),
                      InfoRow('Fine per late day', money(loan.finePerDay)),
                      InfoRow('Started', prettyDate(loan.startDate)),
                      InfoRow('Days covered', '${s.coveredDays} of ${loan.installmentCount}'),
                    ],
                    InfoRow('Payments left', '${s.daysRemaining}'),
                    InfoRow('Next due', s.isCleared ? '—' : prettyDate(s.nextDueDate)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              if (active && !s.isCleared) ...[
                FilledButton.icon(
                  onPressed: _recordPayment,
                  icon: const Icon(Icons.add_card),
                  label: const Text('Record payment'),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _markMissed(s),
                      icon: const Icon(Icons.event_busy),
                      label: const Text('Mark missed'),
                    ),
                  ),
                  // SPEC §3: the UPI button appears only once a UPI ID is set in Settings.
                  if (d.upiReady) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _upi(s),
                        icon: const Icon(Icons.qr_code),
                        label: const Text('Pay via UPI'),
                      ),
                    ),
                  ],
                ]),
              ],
              if (active && s.isCleared)
                FilledButton.icon(
                  onPressed: () => _changeStatus(RecordStatus.completed),
                  icon: const Icon(Icons.task_alt),
                  label: const Text('Mark completed'),
                ),
              if (loan.status == RecordStatus.completed)
                OutlinedButton.icon(
                  onPressed: () => _changeStatus(RecordStatus.archived),
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('Archive loan'),
                ),
              SectionHeader('Payment history', trailing: Text('${d.payments.length} entries')),
              if (d.payments.isEmpty)
                const EmptyState(icon: Icons.history, message: 'No payments recorded yet.')
              else
                Card(
                  child: Column(children: [
                    for (final p in d.payments) PaymentHistoryTile(p, monthly: loan.isMonthly),
                  ]),
                ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}
