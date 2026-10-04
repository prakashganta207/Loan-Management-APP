import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/borrower_service.dart';
import '../../widgets/common.dart';

/// Add (borrower == null) or edit a borrower. Pops with the borrower id on save.
class BorrowerFormScreen extends StatefulWidget {
  const BorrowerFormScreen({super.key, this.borrower});
  final Borrower? borrower;

  @override
  State<BorrowerFormScreen> createState() => _BorrowerFormScreenState();
}

class _BorrowerFormScreenState extends State<BorrowerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.borrower?.name);
  late final _phone = TextEditingController(text: widget.borrower?.phone);
  late final _address = TextEditingController(text: widget.borrower?.address);
  late final _notes = TextEditingController(text: widget.borrower?.notes);
  final _service = BorrowerService();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final existing = widget.borrower;
      int id;
      if (existing == null) {
        id = await _service.create(
            name: _name.text, phone: _phone.text, address: _address.text, notes: _notes.text);
      } else {
        await _service.update(existing.copyWith(
            name: _name.text, phone: _phone.text, address: _address.text, notes: _notes.text));
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
    final editing = widget.borrower != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit borrower' : 'Add borrower')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              autofocus: !editing,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _address,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Address'),
              maxLines: 2,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notes,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(editing ? 'Save changes' : 'Add borrower'),
            ),
          ],
        ),
      ),
    );
  }
}
