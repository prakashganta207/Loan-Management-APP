import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/loan_service.dart';
import '../../widgets/common.dart';
import 'loan_details_screen.dart';
import 'loan_form_screen.dart';

class LoanListScreen extends StatefulWidget {
  const LoanListScreen({super.key});

  @override
  State<LoanListScreen> createState() => _LoanListScreenState();
}

class _LoanListScreenState extends State<LoanListScreen> {
  final _service = LoanService();
  String _status = RecordStatus.active;
  late Future<List<LoanSummary>> _future = _service.summaries(status: _status);

  void _reload() => setState(() => _future = _service.summaries(status: _status));

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) _reload();
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
          child: AsyncView<List<LoanSummary>>(
            future: _future,
            builder: (context, list) {
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.receipt_long,
                  message: _status == RecordStatus.active
                      ? 'No active loans. Tap "New loan" to add one.'
                      : 'No $_status loans.',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final s = list[i];
                  final next = s.isCleared
                      ? 'Fully paid'
                      : 'Next due ${prettyDate(s.nextDueDate)}'
                          '${s.overdueDays > 0 ? ' · ${s.overdueDays}d behind' : ''}';
                  return Card(
                    child: ListTile(
                      title: Text('${s.loan.borrowerName} — ${s.loan.loanName}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(next),
                      trailing: Text(
                        money(s.outstanding),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: s.overdueDays > 0 ? AppColors.missed : null,
                        ),
                      ),
                      onTap: () => _push(LoanDetailsScreen(loanId: s.loan.id!)),
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
