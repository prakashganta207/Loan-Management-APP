import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/loan_service.dart';
import '../../services/upi_service.dart';
import '../../widgets/common.dart';

/// Records money received. Pops with true when something was saved.
class PaymentEntryScreen extends StatefulWidget {
  const PaymentEntryScreen({super.key, required this.loanId});
  final int loanId;

  @override
  State<PaymentEntryScreen> createState() => _PaymentEntryScreenState();
}

class _PaymentEntryScreenState extends State<PaymentEntryScreen> {
  final _service = LoanService();
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _fine = TextEditingController();
  final _note = TextEditingController();

  LoanSummary? _summary;
  String _slot = todayKey();
  bool _fineEdited = false;
  bool _split = true;
  bool _saving = false;
  bool _upiReady = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _fine.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await _service.summary(widget.loanId);
    final upiReady = (await UpiService().config()) != null;
    if (!mounted) return;
    setState(() {
      _summary = s;
      _upiReady = upiReady;
      _slot = s.nextDueDate ?? (s.loan.isMonthly ? s.loan.startDate : todayKey());
      _amount.text = (s.loan.isMonthly
              ? s.nextDueUnpaid
              : round2(math.min(s.loan.installmentAmount, s.outstanding)))
          .toStringAsFixed(2);
      _updateFine();
    });
  }

  Loan get _loan => _summary!.loan;

  void _updateFine() {
    if (_fineEdited || _summary == null) return;
    _fine.text = LoanService.suggestedFine(_loan, _slot, DateTime.now(), unpaid: _slotUnpaid)
        .toStringAsFixed(2);
  }

  /// What is still unpaid on the chosen instalment (monthly late interest is
  /// charged on this part only).
  double get _slotUnpaid {
    final i = LoanService.slotIndex(_loan, _slot);
    if (i == null) return 0;
    final left = round2(LoanService.slotDue(_loan, i) - (_summary!.paidBySlot[_slot] ?? 0));
    return left < 0 ? 0 : left;
  }

  /// Monthly loans: the unpaid instalments the lender can record against.
  List<String> get _monthlySlots {
    final s = _summary!;
    final first = LoanService.slotIndex(_loan, s.nextDueDate ?? _loan.startDate) ?? 0;
    final count = math.max(1, s.daysRemaining);
    return [
      for (var i = first; i < first + count + 12 && i < first + 120; i++)
        if ((s.paidBySlot[LoanService.slotKey(_loan, i)] ?? 0) <
            LoanService.slotDue(_loan, i) - kEps)
          LoanService.slotKey(_loan, i),
    ].take(math.max(count, 1)).toList();
  }

  int get _lateDays => math.max(0, daysBetween(parseDate(_slot), DateTime.now()));

  double get _amountValue => parseAmount(_amount.text) ?? 0;

  Future<void> _save({String? notePrefix}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final note = [if (notePrefix != null) notePrefix, _note.text.trim()]
          .where((s) => s.isNotEmpty)
          .join(' · ');
      final ids = await _service.recordPayment(
        loanId: widget.loanId,
        slotDate: _slot,
        amount: _amountValue,
        fine: parseAmount(_fine.text) ?? 0,
        note: note,
        splitAcrossDays: _split,
      );
      if (!mounted) return;
      showMessage(context,
          'Saved ${money(_amountValue)} as ${ids.length} ledger entr${ids.length == 1 ? 'y' : 'ies'}');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _upi() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await runUpiFlow(context, amount: _amountValue, note: _loan.loanName);
    if (ok && mounted) await _save(notePrefix: 'UPI');
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    if (s == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Record payment')),
          body: const Center(child: CircularProgressIndicator()));
    }
    final monthly = _loan.isMonthly;
    final unit = monthly ? 'instalment' : 'day';
    final extra = _amountValue > _loan.installmentAmount + kEps;
    final days = (_amountValue / _loan.installmentAmount - kEps).ceil();
    final slots = monthly ? _monthlySlots : const <String>[];
    final lateHelp = _lateDays > 0
        ? '$_lateDays day${_lateDays == 1 ? '' : 's'} late'
        : 'On time';
    return Scaffold(
      appBar: AppBar(title: Text('Payment — ${_loan.borrowerName}')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  InfoRow('Loan', _loan.loanName),
                  InfoRow('Outstanding', money(s.outstanding), emphasize: true),
                  InfoRow(monthly ? 'Monthly instalment' : 'Daily payment',
                      '${money(_loan.installmentAmount)} / ${_loan.periodLabel}'),
                  InfoRow(monthly ? 'First unpaid instalment' : 'First unpaid day',
                      prettyDate(s.nextDueDate)),
                  if (monthly && s.accruedLateCharge > 0)
                    InfoRow('Late interest due so far', money(s.accruedLateCharge)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            if (monthly)
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: slots.contains(_slot) ? _slot : (slots.isEmpty ? null : slots.first),
                isExpanded: true,
                decoration: InputDecoration(labelText: 'Instalment this covers', helperText: lateHelp),
                items: [
                  for (final k in slots)
                    DropdownMenuItem(
                      value: k,
                      child: Text('Instalment ${(LoanService.slotIndex(_loan, k) ?? 0) + 1}'
                          ' · due ${prettyDate(k)}'),
                    ),
                ],
                onChanged: (v) => setState(() {
                  if (v != null) _slot = v;
                  _updateFine();
                }),
              )
            else
              DateField(
                label: 'Schedule day this covers',
                value: _slot,
                helperText: lateHelp,
                firstDate: parseDate(_loan.startDate),
                onChanged: (v) => setState(() {
                  _slot = v;
                  _updateFine();
                }),
              ),
            const SizedBox(height: 14),
            AmountField(
              controller: _amount,
              label: 'Amount received',
              onChanged: (_) => setState(() {}),
            ),
            if (extra)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _split,
                onChanged: (v) => setState(() => _split = v),
                title: Text('Apply the extra to following ${unit}s'),
                subtitle: Text(_split
                    ? 'Covers about $days ${unit}s, one ledger entry per $unit'
                    : 'Saved as a single entry on ${prettyDate(_slot)}'),
              ),
            const SizedBox(height: 14),
            AmountField(
              controller: _fine,
              label: monthly ? 'Late interest' : 'Fine',
              required: false,
              allowZero: true,
              helperText: monthly
                  ? '${money(_slotUnpaid)} unpaid × ${_loan.lateInterestPercent}% × '
                      '($_lateDays late − ${_loan.graceDays} grace days) ÷ 30 — you can change it'
                  : '$_lateDays late day(s) × ${money(_loan.finePerDay)} — you can change it',
              onChanged: (_) => _fineEdited = true,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : () => _save(),
              child: const Text('Save payment'),
            ),
            // SPEC §3: only offered once a UPI ID is set in Settings.
            if (_upiReady) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _saving ? null : _upi,
                icon: const Icon(Icons.qr_code),
                label: const Text('Collect via UPI, then save'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
