import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/borrower_service.dart';
import '../../services/loan_service.dart';
import '../../widgets/common.dart';
import '../borrowers/borrower_form_screen.dart';
import 'loan_terms_form.dart';

/// Add Loan. Pops with the new loan id.
class LoanFormScreen extends StatefulWidget {
  const LoanFormScreen({super.key, this.borrowerId});
  final int? borrowerId;

  @override
  State<LoanFormScreen> createState() => _LoanFormScreenState();
}

class _LoanFormScreenState extends State<LoanFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _borrowerService = BorrowerService();
  final _loanService = LoanService();
  final _name = TextEditingController();
  final _terms = LoanTermsController();

  List<Borrower> _borrowers = [];
  int? _borrowerId;
  bool _saving = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _borrowerId = widget.borrowerId;
    _loadBorrowers();
  }

  @override
  void dispose() {
    _name.dispose();
    _terms.dispose();
    super.dispose();
  }

  Future<void> _loadBorrowers() async {
    final list = await _borrowerService.list();
    if (!mounted) return;
    setState(() {
      _borrowers = list;
      _loading = false;
      if (_borrowerId != null && !list.any((b) => b.id == _borrowerId)) _borrowerId = null;
    });
  }

  Future<void> _newBorrower() async {
    final id = await Navigator.push<int>(
        context, MaterialPageRoute(builder: (_) => const BorrowerFormScreen()));
    if (id == null) return;
    _borrowerId = id;
    await _loadBorrowers();
  }

  Future<void> _save() async {
    if (_borrowerId == null) {
      showMessage(context, 'Choose a borrower first', error: true);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final t = _terms;
      final id = await _loanService.createLoan(
        borrowerId: _borrowerId!,
        loanName: _name.text,
        totalPayable: t.totalValue,
        dailyPayment: t.installmentValue,
        durationDays: t.countValue,
        finePerDay: t.fineValue,
        startDate: t.startDate,
        repaymentType: t.type,
        lateInterestPercent: t.interestValue,
        graceDays: t.graceValue,
      );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New loan')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<int>(
                    key: ValueKey('borrowers-${_borrowers.length}-$_borrowerId'),
                    // ignore: deprecated_member_use
                    value: _borrowerId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Borrower *'),
                    items: [
                      for (final b in _borrowers)
                        DropdownMenuItem(
                          value: b.id,
                          child: Text(b.phone == null ? b.name : '${b.name} (${b.phone})'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _borrowerId = v),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _newBorrower,
                      icon: const Icon(Icons.person_add),
                      label: const Text('New borrower'),
                    ),
                  ),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Loan name *', hintText: 'e.g. Shop loan'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),
                  LoanTermsFields(controller: _terms),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('Create loan'),
                  ),
                ],
              ),
            ),
    );
  }
}
