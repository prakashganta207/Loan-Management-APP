import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../services/report_service.dart';
import '../../widgets/common.dart';
import '../loans/payment_history_tile.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reports'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Daily'),
            Tab(text: 'Monthly'),
            Tab(text: 'Overall'),
          ]),
        ),
        body: const TabBarView(children: [_DailyTab(), _MonthlyTab(), _OverallTab()]),
      ),
    );
  }
}

class _DailyTab extends StatefulWidget {
  const _DailyTab();

  @override
  State<_DailyTab> createState() => _DailyTabState();
}

class _DailyTabState extends State<_DailyTab> {
  final _service = ReportService();
  String _date = todayKey();
  late Future<DailyReport> _future = _service.daily(_date);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DateField(
          label: 'Date',
          value: _date,
          lastDate: DateTime.now(),
          onChanged: (v) => setState(() {
            _date = v;
            _future = _service.daily(v);
          }),
        ),
        const SizedBox(height: 12),
        FutureBuilder<DailyReport>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return Text(errorText(snap.error!));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final r = snap.data!;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              StatGrid(children: [
                StatCard(
                  label: 'Loan collections',
                  value: money(r.collected),
                  subtitle: r.expected == null ? null : 'of ${money(r.expected!)} expected',
                  icon: Icons.payments,
                  color: AppColors.paid,
                ),
                StatCard(
                    label: 'Fines', value: money(r.fines), icon: Icons.gavel, color: AppColors.partial),
                StatCard(label: 'Chit contributions', value: money(r.chitCollected), icon: Icons.groups),
                StatCard(label: 'Entries', value: '${r.rows.length}', icon: Icons.list_alt),
              ]),
              const SectionHeader('Transactions'),
              if (r.rows.isEmpty)
                const EmptyState(icon: Icons.receipt_long, message: 'Nothing recorded on this day.')
              else
                Card(
                  child: Column(children: [
                    for (final row in r.rows)
                      PaymentHistoryTile(row.payment,
                          loanName: '${row.borrowerName} — ${row.loanName}'),
                  ]),
                ),
            ]);
          },
        ),
      ],
    );
  }
}

class _MonthlyTab extends StatefulWidget {
  const _MonthlyTab();

  @override
  State<_MonthlyTab> createState() => _MonthlyTabState();
}

class _MonthlyTabState extends State<_MonthlyTab> {
  final _service = ReportService();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<MonthlyReport> _future = _service.monthly(monthKey(_month));

  void _shift(int delta) => setState(() {
        _month = DateTime(_month.year, _month.month + delta);
        _future = _service.monthly(monthKey(_month));
      });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Text(prettyMonth(monthKey(_month)),
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(
              onPressed: isCurrent ? null : () => _shift(1),
              icon: const Icon(Icons.chevron_right)),
        ]),
        const SizedBox(height: 8),
        FutureBuilder<MonthlyReport>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return Text(errorText(snap.error!));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final r = snap.data!;
            return StatGrid(children: [
              StatCard(
                  label: 'Loan collections',
                  value: money(r.loanCollected),
                  subtitle: '${r.paymentCount} payment entries',
                  icon: Icons.payments,
                  color: AppColors.paid),
              StatCard(
                  label: 'Fines', value: money(r.fines), icon: Icons.gavel, color: AppColors.partial),
              StatCard(
                  label: 'Chit contributions', value: money(r.chitCollected), icon: Icons.groups),
              StatCard(label: 'Chit commission', value: money(r.commissions), icon: Icons.percent),
            ]);
          },
        ),
      ],
    );
  }
}

class _OverallTab extends StatefulWidget {
  const _OverallTab();

  @override
  State<_OverallTab> createState() => _OverallTabState();
}

class _OverallTabState extends State<_OverallTab> {
  late final Future<OverallReport> _future = ReportService().overall();

  @override
  Widget build(BuildContext context) {
    return AsyncView<OverallReport>(
      future: _future,
      builder: (context, r) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader('Loans'),
          StatGrid(children: [
            StatCard(label: 'Total lent (payable)', value: money(r.totalLent), icon: Icons.outbound),
            StatCard(
                label: 'Total collected',
                value: money(r.totalCollected),
                icon: Icons.payments,
                color: AppColors.paid),
            StatCard(
                label: 'Outstanding',
                value: money(r.outstanding),
                icon: Icons.account_balance_wallet,
                color: AppColors.missed),
            StatCard(
                label: 'Fines collected',
                value: money(r.totalFines),
                icon: Icons.gavel,
                color: AppColors.partial),
            StatCard(label: 'Active loans', value: '${r.activeLoans}', icon: Icons.play_circle),
            StatCard(label: 'Closed loans', value: '${r.closedLoans}', icon: Icons.task_alt),
          ]),
          const SectionHeader('Chits'),
          StatGrid(children: [
            StatCard(label: 'Active chits', value: '${r.activeChits}', icon: Icons.groups),
            StatCard(label: 'Commission earned', value: money(r.totalCommissions), icon: Icons.percent),
            StatCard(label: 'Dividends paid', value: money(r.totalDividends), icon: Icons.redeem),
            StatCard(
                label: 'Contributions collected', value: money(r.chitCollected), icon: Icons.savings),
          ]),
        ],
      ),
    );
  }
}
