import 'package:flutter/material.dart';

import '../../services/chit_service.dart';
import '../../widgets/common.dart';

/// Add a chit member. Pops with true on save.
class MemberFormScreen extends StatefulWidget {
  const MemberFormScreen({super.key, required this.chitId});
  final int chitId;

  @override
  State<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends State<MemberFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save({bool another = false}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ChitService().addMember(chitId: widget.chitId, name: _name.text, phone: _phone.text);
      if (!mounted) return;
      if (another) {
        showMessage(context, 'Added ${_name.text.trim()}');
        _name.clear();
        _phone.clear();
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Add member')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Member name *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone (optional)'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                  onPressed: _saving ? null : () => _save(), child: const Text('Add member')),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _saving ? null : () => _save(another: true),
                child: const Text('Add and enter another'),
              ),
            ],
          ),
        ),
    );
  }
}
