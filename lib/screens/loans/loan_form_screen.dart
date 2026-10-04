import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/borrower_service.dart';
import '../../services/loan_service.dart';
import '../../widgets/common.dart';
import '../borrowers/borrower_form_screen.dart';

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
  final _total = TextEditingController();
  final _daily = TextEditingController();
  final _duration = TextEditingController();
  final _fine = TextEditingController(text: '0');

  List<Borrower> _borrowers = [];
  int? _borrowerId;
  String _startDate = todayKey();
  bool _durationEdited = false;
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
    for (final c in [_name, _total, _daily, _duration, _fine]) {
      c.dispose();
    }
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

  /// Suggests duration = total ÷ daily until the lender types their own.
  void _suggestDuration() {
    if (_durationEdited) return;
    final total = parseAmount(_total.text);
    final daily = parseAmount(_daily.text);
    if (total != null && daily != null && daily > 0) {
      _duration.text = '${(total / daily - kEps).ceil()}';
    }
  }

  Future<void> _save() async {
    if (_borrowerId == null) {
      showMessage(context, 'Choose a borrower first', error: true);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final id = await _loanService.createLoan(
        borrowerId: _borrowerId!,
        loanName: _name.text,
        totalPayable: parseAmount(_total.text)!,
        dailyPayment: parseAmount(_daily.text)!,
        durationDays: int.parse(_duration.text.trim()),
        finePerDay: parseAmount(_fine.text) ?? 0,
        startDate: _startDate,
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
                  AmountField(
                    controller: _total,
                    label: 'Total payable *',
                    helperText: 'The full amount the borrower will repay',
                    onChanged: (_) => _suggestDuration(),
                  ),
                  const SizedBox(height: 14),
                  AmountField(
                    controller: _daily,
                    label: 'Daily payment *',
                    onChanged: (_) => _suggestDuration(),
                  ),
                  const SizedBox(height: 14),
                  CountField(
                    controller: _duration,
                    label: 'Duration (days) *',
                    helperText: _durationEdited
                        ? 'Set by you'
                        : 'Filled in from total ÷ daily — change it if needed',
                    onChanged: (_) => setState(() => _durationEdited = true),
                  ),
                  const SizedBox(height: 14),
                  AmountField(
                    controller: _fine,
                    label: 'Fine per late day',
                    required: false,
                    allowZero: true,
                  ),
                  const SizedBox(height: 14),
                  DateField(
                    label: 'Start date (first collection day)',
                    value: _startDate,
                    onChanged: (v) => setState(() => _startDate = v),
                  ),
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
