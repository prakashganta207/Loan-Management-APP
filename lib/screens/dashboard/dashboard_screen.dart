import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../services/loan_service.dart';
import '../../services/report_service.dart';
import '../../widgets/common.dart';
import '../loans/loan_details_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _reports = ReportService();
  final _loans = LoanService();
  late Future<DashboardData> _future = _reports.dashboard();

  void _reload() => setState(() => _future = _reports.dashboard());

  Future<void> _refresh() async {
    _reload();
    try {
      await _future;
    } catch (_) {}
  }

  Future<void> _open(String route) async {
    await Navigator.pushNamed(context, route);
    if (mounted) _reload();
  }

  Future<void> _openLoan(int loanId) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => LoanDetailsScreen(loanId: loanId)));
    if (mounted) _reload();
  }

  Future<void> _quickPaid(TodayItem item) async {
    final s = item.summary;
    final amount = round2(math.min(item.stillDue, s.outstanding));
    if (amount <= 0) return;
    try {
      await _loans.recordPayment(
        loanId: s.loan.id!,
        slotDate: s.nextDueDate ?? todayKey(),
        amount: amount,
        note: 'Quick entry',
      );
      if (!mounted) return;
      showMessage(context, 'Recorded ${money(amount)} from ${s.loan.borrowerName}');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _markMissed(TodayItem item) async {
    final s = item.summary;
    final today = todayKey();
    final next = s.nextDueDate;
    final slot = (next != null && next.compareTo(today) <= 0) ? next : today;
    try {
      await _loans.markMissed(loanId: s.loan.id!, slotDate: slot);
      if (!mounted) return;
      showMessage(context, 'Marked ${prettyDate(slot)} as missed for ${s.loan.borrowerName}');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _reload, icon: const Icon(Icons.refresh)),
          IconButton(
              tooltip: 'Settings',
              onPressed: () => _open(Routes.settings),
              icon: const Icon(Icons.settings)),
        ],
      ),
      body: AsyncView<DashboardData>(
        future: _future,
        builder: (context, d) => RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (d.backupDue)
                Card(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.backup),
                    title: const Text('Time to back up'),
                    subtitle: const Text('Your last backup is over a week old.'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(Routes.settings),
                  ),
                ),
              StatGrid(children: [
                StatCard(
                  label: "Today's collection",
                  value: money(d.collected),
                  subtitle: 'of ${money(d.expected)} expected',
                  icon: Icons.payments,
                  color: AppColors.paid,
                ),
                StatCard(
                  label: 'Pending borrowers',
                  value: '${d.pendingBorrowers}',
                  icon: Icons.pending_actions,
                  color: d.pendingBorrowers > 0 ? AppColors.partial : AppColors.paid,
                ),
                StatCard(
                  label: 'Active loans',
                  value: '${d.activeLoans}',
                  icon: Icons.account_balance_wallet,
                  onTap: () => _open(Routes.loans),
                ),
                StatCard(
                  label: 'Active chits',
                  value: '${d.activeChits}',
                  icon: Icons.groups,
                  onTap: () => _open(Routes.chits),
                ),
              ]),
              const SizedBox(height: 12),
              StatGrid(children: [
                _ActionTile(Icons.account_balance_wallet_outlined, 'Loans', () => _open(Routes.loans)),
                _ActionTile(Icons.groups_outlined, 'Chits', () => _open(Routes.chits)),
                _ActionTile(Icons.people_outline, 'Borrowers', () => _open(Routes.borrowers)),
                _ActionTile(Icons.calculate_outlined, 'Chit calculator', () => _open(Routes.calculator)),
                _ActionTile(Icons.bar_chart, 'Reports', () => _open(Routes.reports)),
                _ActionTile(Icons.settings_outlined, 'Settings', () => _open(Routes.settings)),
              ]),
              SectionHeader("Today's collection schedule",
                  trailing: Text('${d.items.where((i) => i.isCollected).length}/${d.items.length} done')),
              if (d.items.isEmpty)
                const EmptyState(
                  icon: Icons.event_available,
                  message: 'No collections due today. Add a loan to start a schedule.',
                )
              else
                ...d.items.map(_scheduleTile),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scheduleTile(TodayItem item) {
    final s = item.summary;
    final behind = s.overdueDays > 0 ? ' · ${s.overdueDays}d behind' : '';
    final partial = item.paidToday > 0 && !item.isCollected ? ' · got ${money(item.paidToday)}' : '';
    Widget trailing;
    if (item.isCollected) {
      trailing = const StatusChip('paid', label: 'Collected');
    } else if (item.missedToday) {
      trailing = const StatusChip('missed', label: 'Missed');
    } else {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton.filledTonal(
          tooltip: 'Mark paid',
          icon: const Icon(Icons.check),
          onPressed: () => _quickPaid(item),
        ),
        IconButton(
          tooltip: 'Mark missed',
          icon: const Icon(Icons.close, color: AppColors.missed),
          onPressed: () => _markMissed(item),
        ),
      ]);
    }
    return Card(
      child: ListTile(
        title: Text(s.loan.borrowerName ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${s.loan.loanName} · due ${money(item.due)}$partial$behind'),
        trailing: trailing,
        onTap: () => _openLoan(s.loan.id!),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.secondaryContainer,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 64,
          child: Row(children: [
            const SizedBox(width: 14),
            Icon(icon, color: scheme.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSecondaryContainer)),
            ),
          ]),
        ),
      ),
    );
  }
}
