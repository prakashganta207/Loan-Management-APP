import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/borrower_service.dart';
import '../../services/loan_service.dart';
import '../../widgets/common.dart';
import '../loans/loan_details_screen.dart';
import '../loans/loan_form_screen.dart';
import '../loans/payment_history_tile.dart';
import 'borrower_form_screen.dart';

class _ProfileData {
  const _ProfileData(this.borrower, this.loans, this.payments);
  final Borrower borrower;
  final List<LoanSummary> loans;
  final List<PaymentRow> payments;
}

class BorrowerProfileScreen extends StatefulWidget {
  const BorrowerProfileScreen({super.key, required this.borrowerId});
  final int borrowerId;

  @override
  State<BorrowerProfileScreen> createState() => _BorrowerProfileScreenState();
}

class _BorrowerProfileScreenState extends State<BorrowerProfileScreen> {
  final _borrowers = BorrowerService();
  final _loans = LoanService();
  late Future<_ProfileData> _future = _load();

  Future<_ProfileData> _load() async => _ProfileData(
        await _borrowers.get(widget.borrowerId),
        await _loans.summaries(borrowerId: widget.borrowerId),
        await _loans.paymentRows(borrowerId: widget.borrowerId),
      );

  void _reload() => setState(() => _future = _load());

  Future<void> _edit(Borrower b) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => BorrowerFormScreen(borrower: b)));
    if (mounted) _reload();
  }

  Future<void> _toggleArchive(Borrower b) async {
    try {
      await _borrowers.setArchived(b.id!, !b.isArchived);
      if (!mounted) return;
      showMessage(context, b.isArchived ? 'Borrower restored' : 'Borrower archived');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _newLoan() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => LoanFormScreen(borrowerId: widget.borrowerId)));
    if (mounted) _reload();
  }

  Future<void> _openLoan(int id) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => LoanDetailsScreen(loanId: id)));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<_ProfileData>(
      future: _future,
      standalone: true,
      builder: (context, d) {
        final b = d.borrower;
        final outstanding = round2(d.loans.fold(0.0, (s, l) => s + l.outstanding));
        final fines = round2(d.loans.fold(0.0, (s, l) => s + l.totalFine));
        final paid = round2(d.loans.fold(0.0, (s, l) => s + l.totalPaid));
        return Scaffold(
          appBar: AppBar(
            title: Text(b.name),
            actions: [
              IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit), onPressed: () => _edit(b)),
              PopupMenuButton<String>(
                onSelected: (_) => _toggleArchive(b),
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'archive',
                      child: Text(b.isArchived ? 'Restore borrower' : 'Archive borrower')),
                ],
              ),
            ],
          ),
          floatingActionButton: b.isArchived
              ? null
              : FloatingActionButton.extended(
                  onPressed: _newLoan,
                  icon: const Icon(Icons.add),
                  label: const Text('New loan'),
                ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    InfoRow('Phone', b.phone ?? '—'),
                    InfoRow('Address', b.address ?? '—'),
                    if (b.notes != null) InfoRow('Notes', b.notes!),
                    InfoRow('Since', prettyDate(b.createdAt)),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              StatGrid(children: [
                StatCard(
                  label: 'Outstanding',
                  value: money(outstanding),
                  icon: Icons.account_balance_wallet,
                  color: outstanding > kEps ? AppColors.missed : AppColors.paid,
                ),
                StatCard(label: 'Total paid', value: money(paid), icon: Icons.payments),
                StatCard(
                    label: 'Fines collected',
                    value: money(fines),
                    icon: Icons.gavel,
                    color: AppColors.partial),
                StatCard(label: 'Loans', value: '${d.loans.length}', icon: Icons.receipt_long),
              ]),
              const SectionHeader('Loans'),
              if (d.loans.isEmpty)
                const EmptyState(icon: Icons.receipt_long, message: 'No loans for this borrower yet.')
              else
                ...d.loans.map((s) => Card(
                      child: ListTile(
                        title: Text(s.loan.loanName,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${money(s.loan.totalPayable)} · '
                            '${money(s.loan.dailyPayment)}/day · from ${prettyDate(s.loan.startDate)}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            StatusChip(s.loan.status),
                            const SizedBox(height: 4),
                            Text(money(s.outstanding),
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                        onTap: () => _openLoan(s.loan.id!),
                      ),
                    )),
              const SectionHeader('Payment history'),
              if (d.payments.isEmpty)
                const EmptyState(icon: Icons.history, message: 'No payments recorded yet.')
              else
                Card(
                  child: Column(children: [
                    for (final r in d.payments) PaymentHistoryTile(r.payment, loanName: r.loanName),
                  ]),
                ),
            ],
          ),
        );
      },
    );
  }
}
