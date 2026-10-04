import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/chit_service.dart';
import '../../widgets/common.dart';
import 'chit_details_screen.dart';
import 'chit_form_screen.dart';

class ChitListScreen extends StatefulWidget {
  const ChitListScreen({super.key});

  @override
  State<ChitListScreen> createState() => _ChitListScreenState();
}

class _ChitListScreenState extends State<ChitListScreen> {
  final _service = ChitService();
  String _status = RecordStatus.active;
  late Future<List<ChitSummary>> _future = _service.listChits(status: _status);

  void _reload() => setState(() => _future = _service.listChits(status: _status));

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chits')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _push(const ChitFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('New chit'),
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
          child: AsyncView<List<ChitSummary>>(
            future: _future,
            builder: (context, list) {
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.groups_outlined,
                  message: _status == RecordStatus.active
                      ? 'No active chits. Tap "New chit" to start one.'
                      : 'No $_status chits.',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final c = list[i];
                  final g = c.group;
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text('${c.currentMonth}')),
                      title: Text(g.chitName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${c.memberCount}/${g.numberOfMembers} members · '
                          'month ${c.currentMonth} of ${g.durationMonths} · '
                          '${c.auctionsDone} auction${c.auctionsDone == 1 ? '' : 's'}'),
                      trailing: Text(g.chitValue == null ? 'No value' : money(g.chitValue!),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () => _push(ChitDetailsScreen(chitId: g.id!)),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
