import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/borrower_service.dart';
import '../../services/chit_loan_service.dart';
import '../../widgets/common.dart';
import 'loan_terms_form.dart';

/// One-time loan setup for a chit auction winner. Pops with the new loan id,
/// or with -1 when the item was dismissed ("Not a loan").
class LoanSetupScreen extends StatefulWidget {
  const LoanSetupScreen({super.key, required this.auctionId});
  final int auctionId;

  @override
  State<LoanSetupScreen> createState() => _LoanSetupScreenState();
}

/// Dropdown value meaning "create a new borrower from the chit member".
const _newBorrower = -1;

class _LoanSetupScreenState extends State<LoanSetupScreen> {
  final _service = ChitLoanService();
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  LoanTermsController? _terms;

  ChitLoanItem? _item;
  List<Borrower> _borrowers = [];
  int _borrowerId = _newBorrower;
  int _remainingChit = 0;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _terms?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final item = await _service.item(widget.auctionId);
      final match = await _service.matchingBorrower(item);
      final borrowers = await BorrowerService().list();
      final remaining = await _service.remainingChitInstallments(item);
      if (!mounted) return;
      setState(() {
        _item = item;
        _borrowers = borrowers;
        _borrowerId = match ?? _newBorrower;
        _remainingChit = remaining;
        _name.text = '${item.chitName} — month ${item.monthNumber} prize';
        // Chit prizes are usually repaid monthly; the lender can switch to daily.
        _terms = LoanTermsController(
          type: RepaymentType.monthly,
          totalPayable: item.prize,
          monthlyFirstDue: dateKey(addMonthsClamped(parseDate(item.auctionDate), 1)),
        );
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _save() async {
    final item = _item!;
    if (item.status != LoanSetupStatus.pending) {
      showMessage(context, 'This winner is not waiting for setup', error: true);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final t = _terms!;
      final loanId = await _service.setUpLoan(
        auctionId: item.auctionId,
        borrowerId: _borrowerId == _newBorrower ? null : _borrowerId,
        loanName: _name.text,
        repaymentType: t.type,
        totalPayable: t.totalValue,
        installment: t.installmentValue,
        installmentCount: t.countValue,
        finePerDay: t.fineValue,
        lateInterestPercent: t.interestValue,
        graceDays: t.graceValue,
        startDate: t.startDate,
      );
      if (!mounted) return;
      showMessage(context, 'Loan created for ${item.memberName}');
      Navigator.pop(context, loanId);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _dismiss() async {
    final item = _item!;
    final ok = await confirmAction(context,
        title: 'Not a loan?',
        message: '${item.memberName}\'s prize will be removed from the waiting list. '
            'You can bring it back from the "Dismissed" filter on the Loans screen.',
        confirmLabel: 'Not a loan');
    if (!ok || !mounted) return;
    try {
      await _service.dismiss(item.auctionId);
      if (mounted) Navigator.pop(context, -1);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final terms = _terms;
    if (item == null || terms == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loan setup')),
        body: Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : Padding(padding: const EdgeInsets.all(24), child: Text(_error!))),
      );
    }
    final phone = item.memberPhone;
    return Scaffold(
      appBar: AppBar(title: const Text('Loan setup')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  InfoRow('Chit winner', item.memberName, emphasize: true),
                  InfoRow('Chit', '${item.chitName}, month ${item.monthNumber}'),
                  InfoRow('Auction date', prettyDate(item.auctionDate)),
                  InfoRow('Prize received', money(item.prize), emphasize: true),
                  InfoRow('Remaining chit instalments for this member', '$_remainingChit'),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              // ignore: deprecated_member_use
              value: _borrowerId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Borrower'),
              items: [
                DropdownMenuItem(
                  value: _newBorrower,
                  child: Text('New borrower: ${item.memberName}'
                      '${phone == null ? '' : ' ($phone)'}'),
                ),
                for (final b in _borrowers)
                  DropdownMenuItem(
                    value: b.id,
                    child: Text(b.phone == null ? b.name : '${b.name} (${b.phone})'),
                  ),
              ],
              onChanged: (v) => setState(() => _borrowerId = v ?? _newBorrower),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Loan name *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 18),
            LoanTermsFields(controller: terms),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Create loan'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _saving ? null : _dismiss,
              icon: const Icon(Icons.block),
              label: const Text('Not a loan'),
            ),
          ],
        ),
      ),
    );
  }
}
