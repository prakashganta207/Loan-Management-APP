import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/chit_calculator.dart';
import '../../services/chit_service.dart';
import '../../widgets/common.dart';

/// Records one month's auction. Pops with true on save.
class AuctionEntryScreen extends StatefulWidget {
  const AuctionEntryScreen({super.key, required this.chitId});
  final int chitId;

  @override
  State<AuctionEntryScreen> createState() => _AuctionEntryScreenState();
}

class _AuctionEntryScreenState extends State<AuctionEntryScreen> {
  final _service = ChitService();
  final _formKey = GlobalKey<FormState>();
  final _winning = TextEditingController();

  ChitGroup? _chit;
  List<int> _openMonths = [];
  List<ChitMember> _eligible = [];
  int? _month;
  int? _winnerId;
  String _date = todayKey();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _winning.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final chit = await _service.getChit(widget.chitId);
    final auctions = await _service.auctions(widget.chitId);
    final members = await _service.members(widget.chitId);
    final done = auctions.map((a) => a.monthNumber).toSet();
    if (!mounted) return;
    setState(() {
      _chit = chit;
      _openMonths = [
        for (var m = 1; m <= chit.durationMonths; m++)
          if (!done.contains(m)) m
      ];
      _month = _openMonths.isEmpty ? null : _openMonths.first;
      // Members who have already won are excluded here AND rejected by the service.
      _eligible = members
          .where((m) => !m.hasWon && m.membershipStatus == MemberStatus.active)
          .toList();
    });
  }

  ChitCalculation? _preview;
  String? _previewError;

  void _recalc() {
    final chit = _chit;
    final w = parseAmount(_winning.text);
    if (chit == null || chit.chitValue == null || w == null) {
      setState(() {
        _preview = null;
        _previewError = null;
      });
      return;
    }
    try {
      final c = ChitCalculator.calculate(
        chitValue: chit.chitValue!,
        members: chit.numberOfMembers,
        winningAmount: w,
        commissionPercent: chit.commissionPercent,
        commissionMode: chit.commissionMode,
      );
      setState(() {
        _preview = c;
        _previewError = null;
      });
    } catch (e) {
      setState(() {
        _preview = null;
        _previewError = errorText(e);
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_month == null || _winnerId == null) {
      showMessage(context, 'Choose the month and the winner', error: true);
      return;
    }
    final winner = _eligible.firstWhere((m) => m.id == _winnerId);
    final ok = await confirmAction(context,
        title: 'Save month $_month auction?',
        message: '${winner.memberName} receives ${money(_preview?.winnerPayout ?? 0)}. '
            'They cannot win again in this chit, and this month is locked once saved.',
        confirmLabel: 'Save auction');
    if (!ok) return;
    setState(() => _saving = true);
    try {
      await _service.recordAuction(
        chitId: widget.chitId,
        monthNumber: _month!,
        winnerMemberId: _winnerId!,
        winningAmount: parseAmount(_winning.text)!,
        auctionDate: _date,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chit = _chit;
    if (chit == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Record auction')),
          body: const Center(child: CircularProgressIndicator()));
    }
    final p = _preview;
    return Scaffold(
      appBar: AppBar(title: Text('Auction — ${chit.chitName}')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            InfoRow('Chit value', chit.chitValue == null ? 'Not set' : money(chit.chitValue!)),
            InfoRow('Commission', '${chit.commissionPercent}%'),
            InfoRow('Commission paid by', CommissionMode.label(chit.commissionMode)),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              // ignore: deprecated_member_use
              value: _month,
              decoration: const InputDecoration(labelText: 'Month'),
              items: [
                for (final m in _openMonths) DropdownMenuItem(value: m, child: Text('Month $m')),
              ],
              onChanged: (v) => setState(() => _month = v),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              // ignore: deprecated_member_use
              value: _winnerId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Winner',
                helperText: '${_eligible.length} member${_eligible.length == 1 ? '' : 's'} '
                    'can still win',
              ),
              items: [
                for (final m in _eligible)
                  DropdownMenuItem(value: m.id, child: Text(m.memberName)),
              ],
              onChanged: (v) => setState(() => _winnerId = v),
            ),
            const SizedBox(height: 14),
            AmountField(
              controller: _winning,
              label: 'Winning amount (auctioned price the winner accepted)',
              onChanged: (_) => _recalc(),
            ),
            const SizedBox(height: 14),
            DateField(
                label: 'Auction date', value: _date, onChanged: (v) => setState(() => _date = v)),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: p == null
                    ? Text(_previewError ?? 'Enter the winning amount to see the split.',
                        style: TextStyle(
                            color: _previewError == null
                                ? null
                                : Theme.of(context).colorScheme.error))
                    : ChitSplitDetails(p),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving || p == null ? null : _save,
              child: const Text('Save auction'),
            ),
          ],
        ),
      ),
    );
  }
}
