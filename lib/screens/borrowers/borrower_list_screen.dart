import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../services/borrower_service.dart';
import '../../widgets/common.dart';
import 'borrower_form_screen.dart';
import 'borrower_profile_screen.dart';

class BorrowerListScreen extends StatefulWidget {
  const BorrowerListScreen({super.key});

  @override
  State<BorrowerListScreen> createState() => _BorrowerListScreenState();
}

class _BorrowerListScreenState extends State<BorrowerListScreen> {
  final _service = BorrowerService();
  String _query = '';
  bool _showArchived = false;
  late Future<List<BorrowerWithBalance>> _future = _load();

  Future<List<BorrowerWithBalance>> _load() =>
      _service.listWithBalances(includeArchived: _showArchived, query: _query);

  void _reload() => setState(() => _future = _load());

  Future<void> _add() async {
    final id = await Navigator.push<int>(
        context, MaterialPageRoute(builder: (_) => const BorrowerFormScreen()));
    if (!mounted) return;
    _reload();
    if (id != null) await _openProfile(id);
  }

  Future<void> _openProfile(int id) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => BorrowerProfileScreen(borrowerId: id)));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Borrowers'),
        actions: [
          IconButton(
            tooltip: _showArchived ? 'Hide archived' : 'Show archived',
            icon: Icon(_showArchived ? Icons.inventory_2 : Icons.inventory_2_outlined),
            onPressed: () {
              _showArchived = !_showArchived;
              _reload();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add),
        label: const Text('Add borrower'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search by name or phone',
            ),
            onChanged: (v) {
              _query = v;
              _reload();
            },
          ),
        ),
        Expanded(
          child: AsyncView<List<BorrowerWithBalance>>(
            future: _future,
            builder: (context, list) {
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.people_outline,
                  message: _query.isEmpty
                      ? 'No borrowers yet. Add the first person you lend to.'
                      : 'No one matches "$_query".',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final item = list[i];
                  final b = item.borrower;
                  final owes = item.outstanding > kEps;
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                          child: Text(b.name.isEmpty ? '?' : b.name[0].toUpperCase())),
                      title: Text(b.isArchived ? '${b.name} (archived)' : b.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([
                        b.phone ?? 'No phone',
                        if (item.activeLoans > 0)
                          '${item.activeLoans} active loan${item.activeLoans == 1 ? '' : 's'}',
                      ].join(' · ')),
                      trailing: Text(
                        owes ? money(item.outstanding) : 'Clear',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: owes ? AppColors.missed : AppColors.paid,
                        ),
                      ),
                      onTap: () => _openProfile(b.id!),
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
