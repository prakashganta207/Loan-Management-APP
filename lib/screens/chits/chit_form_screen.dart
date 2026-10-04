import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/chit_service.dart';
import '../../widgets/common.dart';

/// Create (chit == null) or edit a chit. Pops with the chit id.
class ChitFormScreen extends StatefulWidget {
  const ChitFormScreen({super.key, this.chit});
  final ChitGroup? chit;

  @override
  State<ChitFormScreen> createState() => _ChitFormScreenState();
}

class _ChitFormScreenState extends State<ChitFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = ChitService();
  late final _name = TextEditingController(text: widget.chit?.chitName);
  late final _value = TextEditingController(text: widget.chit?.chitValue?.toStringAsFixed(0));
  late final _members = TextEditingController(text: widget.chit?.numberOfMembers.toString());
  late final _months = TextEditingController(text: widget.chit?.durationMonths.toString());
  late final _commission =
      TextEditingController(text: (widget.chit?.commissionPercent ?? 5).toString());
  late String _startDate = widget.chit?.startDate ?? todayKey();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _value, _members, _months, _commission]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final value = _value.text.trim().isEmpty ? null : parseAmount(_value.text);
      final members = int.parse(_members.text.trim());
      final months = int.parse(_months.text.trim());
      final commission = parseAmount(_commission.text) ?? 0;
      final existing = widget.chit;
      int id;
      if (existing == null) {
        id = await _service.createChit(
          name: _name.text,
          chitValue: value,
          members: members,
          durationMonths: months,
          commissionPercent: commission,
          startDate: _startDate,
        );
      } else {
        await _service.updateChit(
          id: existing.id!,
          name: _name.text,
          chitValue: value,
          members: members,
          durationMonths: months,
          commissionPercent: commission,
          startDate: _startDate,
        );
        id = existing.id!;
      }
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.chit != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit chit' : 'New chit')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Chit name *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            AmountField(
              controller: _value,
              label: 'Chit value',
              required: false,
              helperText: 'Optional now, but needed before the first auction',
            ),
            const SizedBox(height: 14),
            CountField(controller: _members, label: 'Number of members *'),
            const SizedBox(height: 14),
            CountField(controller: _months, label: 'Duration (months) *'),
            const SizedBox(height: 14),
            TextFormField(
              controller: _commission,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Organizer commission', suffixText: '%'),
              validator: (v) {
                final n = parseAmount(v ?? '');
                if (n == null) return 'Enter a number (0 if none)';
                if (n < 0 || n > 100) return 'Between 0 and 100';
                return null;
              },
            ),
            const SizedBox(height: 14),
            DateField(
              label: 'Start date',
              value: _startDate,
              onChanged: (v) => setState(() => _startDate = v),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(editing ? 'Save changes' : 'Create chit'),
            ),
          ],
        ),
      ),
    );
  }
}
