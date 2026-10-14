import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/chit_loan_service.dart';
import '../../services/loan_service.dart';
import '../../widgets/common.dart';
import 'loan_details_screen.dart';
import 'loan_form_screen.dart';
import 'loan_setup_screen.dart';

class _LoanListData {
  const _LoanListData(this.loans, this.waiting, this.dismissed);
  final List<LoanSummary> loans;
  final List<ChitLoanItem> waiting;
  final List<ChitLoanItem> dismissed;
}

class LoanListScreen extends StatefulWidget {
  const LoanListScreen({super.key});

  @override
  State<LoanListScreen> createState() => _LoanListScreenState();
}

class _LoanListScreenState extends State<LoanListScreen> {
  final _service = LoanService();
  final _chitLoans = ChitLoanService();
  String _status = RecordStatus.active;

  /// Shows dismissed chit winners instead of the ones waiting for setup.
  bool _showDismissed = false;
  late Future<_LoanListData> _future = _load();

  Future<_LoanListData> _load() async => _LoanListData(
        await _service.summaries(status: _status),
        await _chitLoans.items(),
        await _chitLoans.items(status: LoanSetupStatus.dismissed),
      );

  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) _reload();
  }

  Future<void> _setUp(ChitLoanItem item) async {
    final loanId = await Navigator.push<int>(
        context, MaterialPageRoute(builder: (_) => LoanSetupScreen(auctionId: item.auctionId)));
    if (!mounted) return;
    _reload();
    if (loanId != null && loanId > 0) await _push(LoanDetailsScreen(loanId: loanId));
  }

  Future<void> _dismiss(ChitLoanItem item) async {
    final ok = await confirmAction(context,
        title: 'Not a loan?',
        message: '${item.memberName}\'s prize from ${item.chitName} will be removed from the '
            'waiting list. You can restore it from "Dismissed".',
        confirmLabel: 'Not a loan');
    if (!ok) return;
    await _run(() => _chitLoans.dismiss(item.auctionId), 'Moved to Dismissed');
  }

  Future<void> _restore(ChitLoanItem item) =>
      _run(() => _chitLoans.restore(item.auctionId), 'Back in the waiting list');

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (!mounted) return;
      showMessage(context, done);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loans')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _push(const LoanFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('New loan'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: RecordStatus.active, label: Text('Active')),
              ButtonSegment(value: RecordStatus.completed, label: Text('Completed')),
              ButtonSegment(value: RecordStatus.archived, label: Text('Archived')),
            ],
            selected: {_status},
            onSelectionChanged: (s) {
              _status = s.first;
              _reload();
            },
          ),
        ),
        Expanded(
          child: AsyncView<_LoanListData>(
            future: _future,
            builder: (context, d) => ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              children: [
                ..._waitingSection(d),
                if (d.loans.isEmpty)
                  EmptyState(
                    icon: Icons.receipt_long,
                    message: _status == RecordStatus.active
                        ? 'No active loans. Tap "New loan" to add one.'
                        : 'No $_status loans.',
                  )
                else
                  for (final s in d.loans) _loanTile(s),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  List<Widget> _waitingSection(_LoanListData d) {
    if (d.waiting.isEmpty && d.dismissed.isEmpty) return const [];
    final list = _showDismissed ? d.dismissed : d.waiting;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
        child: Wrap(spacing: 8, runSpacing: 4, children: [
          ChoiceChip(
            label: Text('Waiting for setup (${d.waiting.length})'),
            selected: !_showDismissed,
            onSelected: (_) => setState(() => _showDismissed = false),
          ),
          ChoiceChip(
            label: Text('Dismissed (${d.dismissed.length})'),
            selected: _showDismissed,
            onSelected: (_) => setState(() => _showDismissed = true),
          ),
        ]),
      ),
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(_showDismissed ? 'Nothing dismissed.' : 'No chit winners waiting.',
              textAlign: TextAlign.center),
        )
      else
        for (final item in list)
          Card(
            color: _showDismissed ? null : Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.emoji_events_outlined),
              title: Text(item.memberName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${item.chitName} · month ${item.monthNumber}\n'
                  'Prize ${money(item.prize)} · ${prettyDate(item.auctionDate)}'),
              isThreeLine: true,
              trailing: _showDismissed
                  ? TextButton(onPressed: () => _restore(item), child: const Text('Restore'))
                  : IconButton(
                      tooltip: 'Not a loan',
                      icon: const Icon(Icons.close),
                      onPressed: () => _dismiss(item),
                    ),
              onTap: _showDismissed ? null : () => _setUp(item),
            ),
          ),
      const Divider(height: 24),
    ];
  }

  Widget _loanTile(LoanSummary s) {
    final l = s.loan;
    final behind = l.isMonthly
        ? (s.overdueInstallments > 0 ? ' · ${s.overdueInstallments} overdue' : '')
        : (s.overdueDays > 0 ? ' · ${s.overdueDays}d behind' : '');
    final next = s.isCleared ? 'Fully paid' : 'Next due ${prettyDate(s.nextDueDate)}$behind';
    return Card(
      child: ListTile(
        title: Text('${l.borrowerName} — ${l.loanName}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${money(l.installmentAmount)} / ${l.periodLabel} · $next'),
        trailing: Text(
          money(s.outstanding),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: s.overdueDays > 0 ? AppColors.missed : null,
          ),
        ),
        onTap: () => _push(LoanDetailsScreen(loanId: l.id!)),
      ),
    );
  }
}
