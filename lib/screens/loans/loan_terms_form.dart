import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Holds what the lender types for a loan's repayment terms. Shared by the
/// "New loan" form and the chit-winner Loan Setup screen.
class LoanTermsController {
  LoanTermsController({
    this.type = RepaymentType.daily,
    double? totalPayable,
    String? dailyStart,
    String? monthlyFirstDue,
  })  : dailyStart = dailyStart ?? todayKey(),
        monthlyFirstDue = monthlyFirstDue ?? dateKey(addMonthsClamped(DateTime.now(), 1)) {
    if (totalPayable != null) total.text = totalPayable.toStringAsFixed(2);
  }

  String type;
  final total = TextEditingController();

  /// Daily payment or monthly instalment.
  final installment = TextEditingController();

  /// Days or months.
  final count = TextEditingController();
  final fine = TextEditingController(text: '0');
  final interest = TextEditingController(text: '0');
  final grace = TextEditingController(text: '0');
  String dailyStart;
  String monthlyFirstDue;

  /// Daily: days are suggested from total ÷ daily until typed by hand.
  bool countEdited = false;

  /// Monthly: the instalment is suggested from total ÷ months until typed by hand.
  bool installmentEdited = false;

  bool get isMonthly => type == RepaymentType.monthly;
  String get startDate => isMonthly ? monthlyFirstDue : dailyStart;
  double get totalValue => parseAmount(total.text) ?? 0;
  double get installmentValue => parseAmount(installment.text) ?? 0;
  int get countValue => int.tryParse(count.text.trim()) ?? 0;
  double get fineValue => isMonthly ? 0 : (parseAmount(fine.text) ?? 0);
  double get interestValue => isMonthly ? (parseAmount(interest.text) ?? 0) : 0;
  int get graceValue => isMonthly ? (int.tryParse(grace.text.trim()) ?? 0) : 0;

  /// Fills in the field the lender hasn't typed yet.
  void suggest() {
    final t = parseAmount(total.text);
    if (isMonthly) {
      final months = int.tryParse(count.text.trim());
      if (!installmentEdited && t != null && months != null && months > 0) {
        installment.text = round2(t / months).toStringAsFixed(2);
      }
    } else {
      final daily = parseAmount(installment.text);
      if (!countEdited && t != null && daily != null && daily > 0) {
        count.text = '${(t / daily - kEps).ceil()}';
      }
    }
  }

  void dispose() {
    for (final c in [total, installment, count, fine, interest, grace]) {
      c.dispose();
    }
  }
}

/// Repayment type first, then the fields for that type.
class LoanTermsFields extends StatefulWidget {
  const LoanTermsFields({super.key, required this.controller});
  final LoanTermsController controller;

  @override
  State<LoanTermsFields> createState() => _LoanTermsFieldsState();
}

class _LoanTermsFieldsState extends State<LoanTermsFields> {
  LoanTermsController get c => widget.controller;

  void _changed() => setState(c.suggest);

  @override
  Widget build(BuildContext context) {
    final monthly = c.isMonthly;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Repayment type', style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 6),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: RepaymentType.daily, label: Text('Daily')),
          ButtonSegment(value: RepaymentType.monthly, label: Text('Monthly')),
        ],
        selected: {c.type},
        onSelectionChanged: (s) => setState(() {
          c.type = s.first;
          // The two types use the instalment/count fields differently.
          c.installment.clear();
          c.count.clear();
          c.countEdited = false;
          c.installmentEdited = false;
        }),
      ),
      const SizedBox(height: 14),
      AmountField(
        controller: c.total,
        label: 'Total payable *',
        helperText: 'The full amount the borrower will repay',
        onChanged: (_) => _changed(),
      ),
      const SizedBox(height: 14),
      if (!monthly) ...[
        AmountField(
          controller: c.installment,
          label: 'Daily payment *',
          onChanged: (_) => _changed(),
        ),
        const SizedBox(height: 14),
        CountField(
          controller: c.count,
          label: 'Duration (days) *',
          helperText: c.countEdited
              ? 'Set by you'
              : 'Filled in from total ÷ daily — change it if needed',
          onChanged: (_) => setState(() => c.countEdited = true),
        ),
        const SizedBox(height: 14),
        AmountField(
          controller: c.fine,
          label: 'Fine per late day',
          required: false,
          allowZero: true,
        ),
        const SizedBox(height: 14),
        DateField(
          label: 'Start date (first collection day)',
          value: c.dailyStart,
          onChanged: (v) => setState(() => c.dailyStart = v),
        ),
      ] else ...[
        CountField(
          controller: c.count,
          label: 'Number of months *',
          onChanged: (_) => _changed(),
        ),
        const SizedBox(height: 14),
        AmountField(
          controller: c.installment,
          label: 'Monthly instalment *',
          helperText: c.installmentEdited
              ? 'Set by you'
              : 'Filled in from total ÷ months — change it if needed',
          onChanged: (_) => setState(() => c.installmentEdited = true),
        ),
        const SizedBox(height: 14),
        DateField(
          label: 'First due date',
          value: c.monthlyFirstDue,
          helperText: 'Later instalments fall on the same day each month',
          onChanged: (v) => setState(() => c.monthlyFirstDue = v),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: c.interest,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: const InputDecoration(
            labelText: 'Late interest',
            suffixText: '% per month',
            helperText: 'Simple interest on an overdue instalment only',
          ),
          validator: (v) {
            final n = parseAmount(v ?? '');
            if (n == null) return 'Enter a number (0 if none)';
            if (n < 0 || n > 100) return 'Between 0 and 100';
            return null;
          },
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: c.grace,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Grace days',
            helperText: 'Days after the due date before late interest starts',
          ),
          validator: (v) => int.tryParse(v?.trim() ?? '') == null ? 'Enter 0 or more' : null,
        ),
      ],
    ]);
  }
}
