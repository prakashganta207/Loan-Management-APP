import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/loan_service.dart';
import '../../services/upi_service.dart';
import '../../widgets/common.dart';
import 'payment_entry_screen.dart';
import 'payment_history_tile.dart';

class _LoanData {
  const _LoanData(this.summary, this.payments, this.upiReady);
  final LoanSummary summary;
  final List<LoanPayment> payments;
  final bool upiReady;
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
    return _LoanData(
      await _service.summary(widget.loanId),
      payments.reversed.toList(),
      (await UpiService().config()) != null,
    );
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _recordPayment() async {
    final saved = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => PaymentEntryScreen(loanId: widget.loanId)));
    if (saved == true && mounted) _reload();
  }

  Future<void> _markMissed(LoanSummary s) async {
    final today = todayKey();
    final next = s.nextDueDate;
    final slot = (next != null && next.compareTo(today) <= 0) ? next : today;
    final ok = await confirmAction(context,
        title: 'Mark as missed?',
        message: 'Adds a "missed" entry for ${prettyDate(slot)}. Nothing is charged now; '
            'the fine is added when the borrower pays late.',
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
    final suggested = round2(math.min(s.loan.dailyPayment, s.outstanding));
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
                        child: Text('${s.overdueDays} day${s.overdueDays == 1 ? '' : 's'} behind schedule',
                            style: const TextStyle(color: AppColors.missed, fontWeight: FontWeight.w600)),
                      ),
                    const Divider(height: 24),
                    InfoRow('Total payable', money(loan.totalPayable)),
                    InfoRow('Paid so far', money(s.totalPaid)),
                    InfoRow('Fines collected', money(s.totalFine)),
                    InfoRow('Daily payment', money(loan.dailyPayment)),
                    InfoRow('Fine per late day', money(loan.finePerDay)),
                    InfoRow('Started', prettyDate(loan.startDate)),
                    InfoRow('Days covered', '${s.coveredDays} of ${loan.durationDays}'),
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: d.upiReady
                          ? () => _upi(s)
                          : () => showMessage(context, 'Add your UPI ID in Settings first'),
                      icon: const Icon(Icons.qr_code),
                      label: const Text('Pay via UPI'),
                    ),
                  ),
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
                  child: Column(children: [for (final p in d.payments) PaymentHistoryTile(p)]),
                ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}
