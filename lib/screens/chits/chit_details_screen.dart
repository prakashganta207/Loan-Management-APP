import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/chit_service.dart';
import '../../widgets/common.dart';
import 'auction_entry_screen.dart';
import 'chit_form_screen.dart';
import 'member_form_screen.dart';

class _ChitData {
  const _ChitData(this.summary, this.members, this.auctions);
  final ChitSummary summary;
  final List<ChitMember> members;
  final List<ChitAuction> auctions;
}

class ChitDetailsScreen extends StatefulWidget {
  const ChitDetailsScreen({super.key, required this.chitId});
  final int chitId;

  @override
  State<ChitDetailsScreen> createState() => _ChitDetailsScreenState();
}

class _ChitDetailsScreenState extends State<ChitDetailsScreen> {
  final _service = ChitService();
  late Future<_ChitData> _future = _load();

  Future<_ChitData> _load() async => _ChitData(
        await _service.summary(widget.chitId),
        await _service.members(widget.chitId),
        await _service.auctions(widget.chitId),
      );

  void _reload() => setState(() => _future = _load());

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) _reload();
  }

  Future<void> _changeStatus(ChitGroup g, String status) async {
    final ok = await confirmAction(context,
        title: status == RecordStatus.completed ? 'Mark chit completed?' : 'Archive chit?',
        message: 'Records are kept. You cannot add members or auctions afterwards.',
        confirmLabel: status == RecordStatus.completed ? 'Mark completed' : 'Archive');
    if (!ok) return;
    try {
      await _service.setStatus(g.id!, status);
      if (mounted) _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<_ChitData>(
      future: _future,
      standalone: true,
      builder: (context, d) {
        final s = d.summary;
        final g = s.group;
        final next = RecordStatus.next(g.status);
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Text(g.chitName),
              actions: [
                IconButton(
                  tooltip: 'Edit chit',
                  icon: const Icon(Icons.edit),
                  onPressed: () => _push(ChitFormScreen(chit: g)),
                ),
                if (next != null)
                  PopupMenuButton<String>(
                    onSelected: (v) => _changeStatus(g, v),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: next,
                        child: Text(next == RecordStatus.completed ? 'Mark completed' : 'Archive'),
                      ),
                    ],
                  ),
              ],
            ),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                          child: Text(g.chitValue == null ? 'Value not set' : money(g.chitValue!),
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                        ),
                        StatusChip(g.status),
                      ]),
                      InfoRow('Members', '${s.memberCount} of ${g.numberOfMembers}'),
                      InfoRow('Month', '${s.currentMonth} of ${g.durationMonths}'),
                      InfoRow('Commission earned', money(s.totalCommission)),
                      InfoRow('Dividends paid out', money(s.totalDividends)),
                    ]),
                  ),
                ),
              ),
              const TabBar(tabs: [
                Tab(text: 'Members'),
                Tab(text: 'Auctions'),
                Tab(text: 'Contributions'),
              ]),
              Expanded(
                child: TabBarView(children: [
                  _membersTab(s, d.members),
                  _auctionsTab(s, d),
                  _ContributionsTab(
                    key: ValueKey('contrib-${d.auctions.length}-${d.members.length}'),
                    summary: s,
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _membersTab(ChitSummary s, List<ChitMember> members) {
    final canAdd = s.group.status == RecordStatus.active && !s.isFull;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        FilledButton.icon(
          onPressed: canAdd ? () => _push(MemberFormScreen(chitId: s.group.id!)) : null,
          icon: const Icon(Icons.person_add),
          label: Text(s.isFull ? 'All ${s.group.numberOfMembers} seats filled' : 'Add member'),
        ),
        const SizedBox(height: 8),
        if (members.isEmpty)
          const EmptyState(icon: Icons.group_add, message: 'No members yet.')
        else
          for (var i = 0; i < members.length; i++)
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(members[i].memberName),
                subtitle: Text(members[i].phone ?? 'No phone'),
                trailing: members[i].hasWon
                    ? const StatusChip('completed', label: 'Won')
                    : const StatusChip('pending', label: 'Not won'),
              ),
            ),
      ],
    );
  }

  Widget _auctionsTab(ChitSummary s, _ChitData d) {
    final g = s.group;
    final allDone = d.auctions.length >= g.durationMonths;
    final eligible = d.members.any((m) => !m.hasWon && m.membershipStatus == MemberStatus.active);
    String? blocker;
    if (g.status != RecordStatus.active) {
      blocker = 'This chit is ${g.status}';
    } else if (g.chitValue == null) {
      blocker = 'Set the chit value (edit) to record auctions';
    } else if (allDone) {
      blocker = 'All ${g.durationMonths} months auctioned';
    } else if (!eligible) {
      blocker = 'No members left who have not won';
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        FilledButton.icon(
          onPressed:
              blocker == null ? () => _push(AuctionEntryScreen(chitId: g.id!)) : null,
          icon: const Icon(Icons.gavel),
          label: const Text('Record auction'),
        ),
        if (blocker != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(blocker, textAlign: TextAlign.center),
          ),
        const SizedBox(height: 8),
        if (d.auctions.isEmpty)
          const EmptyState(icon: Icons.gavel, message: 'No auctions yet.')
        else
          for (final a in d.auctions.reversed)
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text('${a.monthNumber}')),
                title: Text(a.winnerName ?? 'Member #${a.winnerMemberId}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Won at ${money(a.winningAmount)} on ${prettyDate(a.auctionDate)}'
                    ' · received ${money(a.winnerPayout)}\n'
                    'Dividend ${money(a.dividendPerMember)} per member · '
                    'commission ${money(a.commissionAmount)}'),
                isThreeLine: true,
              ),
            ),
      ],
    );
  }
}

class _ContributionsTab extends StatefulWidget {
  const _ContributionsTab({super.key, required this.summary});
  final ChitSummary summary;

  @override
  State<_ContributionsTab> createState() => _ContributionsTabState();
}

class _ContributionsTabState extends State<_ContributionsTab> {
  final _service = ChitService();
  late int _month = widget.summary.currentMonth;
  late Future<List<ChitContribution>> _future = _load();

  Future<List<ChitContribution>> _load() =>
      _service.contributions(widget.summary.group.id!, _month);

  void _reload() => setState(() => _future = _load());

  Future<void> _generate() async {
    try {
      final n = await _service.ensureContributions(widget.summary.group.id!, _month);
      if (!mounted) return;
      showMessage(context, n == 0 ? 'Already up to date' : 'Added $n members for month $_month');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _toggle(ChitContribution c, bool paid) async {
    try {
      await _service.setContributionPaid(c.id!, paid);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.summary.group;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          IconButton(
            onPressed: _month > 1
                ? () {
                    _month--;
                    _reload();
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text('Month $_month of ${g.durationMonths}',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(
            onPressed: _month < g.durationMonths
                ? () {
                    _month++;
                    _reload();
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
        FutureBuilder<List<ChitContribution>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return Text(errorText(snap.error!));
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final list = snap.data!;
            if (list.isEmpty) {
              return EmptyState(
                icon: Icons.playlist_add,
                message: 'No contribution list for month $_month yet.',
                action: FilledButton(
                  onPressed: widget.summary.memberCount == 0 ? null : _generate,
                  child: Text('Create list for month $_month'),
                ),
              );
            }
            final collected = list.where((c) => c.isPaid).fold(0.0, (s, c) => s + c.amount);
            final total = list.fold(0.0, (s, c) => s + c.amount);
            final paidCount = list.where((c) => c.isPaid).length;
            return Column(children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    InfoRow('Collected', '${money(collected)} of ${money(total)}',
                        emphasize: true,
                        color: collected >= total - kEps ? AppColors.paid : AppColors.partial),
                    InfoRow('Members paid', '$paidCount of ${list.length}'),
                  ]),
                ),
              ),
              if (list.length < widget.summary.memberCount)
                TextButton(onPressed: _generate, child: const Text('Add newly joined members')),
              for (final c in list)
                Card(
                  child: CheckboxListTile(
                    value: c.isPaid,
                    onChanged: (v) => _toggle(c, v ?? false),
                    title: Text(c.memberName ?? 'Member'),
                    subtitle: Text(c.isPaid
                        ? '${money(c.amount)} · paid ${prettyDate(c.paymentDate)}'
                        : '${money(c.amount)} · pending'),
                  ),
                ),
            ]);
          },
        ),
      ],
    );
  }
}
