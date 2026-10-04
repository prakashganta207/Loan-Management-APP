import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/format.dart';
import '../../core/routes.dart';
import '../../services/auth_service.dart';
import '../../services/backup_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService();
  final _auth = AuthService();
  final _backup = BackupService();

  bool _loading = true;
  bool _busy = false;
  String? _lastBackup;
  bool _reminder = false;
  String? _upiId;
  String? _payee;
  AppUser? _user;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final last = await _settings.get(SettingsKeys.lastBackupAt);
    final reminder = await _settings.getBool(SettingsKeys.backupReminder);
    final upi = await _settings.get(SettingsKeys.upiId);
    final payee = await _settings.get(SettingsKeys.upiPayeeName);
    final user = await _auth.currentUser();
    var bio = false;
    try {
      final la = LocalAuthentication();
      bio = await la.isDeviceSupported() && await la.canCheckBiometrics;
    } catch (_) {
      bio = false;
    }
    if (!mounted) return;
    setState(() {
      _lastBackup = last;
      _reminder = reminder;
      _upiId = upi;
      _payee = payee;
      _user = user;
      _biometricAvailable = bio;
      _loading = false;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _export() => _run(() async {
        final file = await _backup.exportBackup();
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Backup saved'),
            content: SelectableText('Saved to:\n${file.path}\n\n'
                'Copy this file to Google Drive, a computer or another phone so it survives '
                'if this phone is lost.'),
            actions: [
              TextButton(
                onPressed: () => Clipboard.setData(ClipboardData(text: file.path)),
                child: const Text('Copy path'),
              ),
              FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done')),
            ],
          ),
        );
      });

  Future<void> _restore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    final first = await confirmAction(context,
        title: 'Restore this backup?',
        message: 'Every borrower, loan, payment and chit on this phone will be REPLACED by the '
            'contents of the backup. Your login stays the same.',
        confirmLabel: 'Continue');
    if (!first || !mounted) return;
    final second = await confirmAction(context,
        title: 'This cannot be undone',
        message: 'Tip: export a backup of the current data first if you might need it.',
        confirmLabel: 'Replace my data',
        destructive: true);
    if (!second) return;
    setState(() => _busy = true);
    try {
      await _backup.restoreFromFile(path);
      if (!mounted) return;
      showMessage(context, 'Backup restored');
      Navigator.pushNamedAndRemoveUntil(context, Routes.dashboard, (_) => false);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, errorText(e), error: true);
      }
    }
  }

  Future<void> _changePassword() async {
    final done = await showDialog<bool>(context: context, builder: (_) => const _PasswordDialog());
    if (done == true && mounted) showMessage(context, 'Password changed');
  }

  Future<void> _togglePin(bool enable) async {
    if (!enable) {
      await _run(() => _auth.setPin(null));
      return;
    }
    final pin = await promptText(context,
        title: 'Set a PIN',
        label: '4–6 digits',
        keyboardType: TextInputType.number,
        obscure: true);
    if (pin == null || pin.trim().isEmpty) return;
    await _run(() => _auth.setPin(pin.trim()));
  }

  Future<void> _toggleBiometric(bool enable) async {
    if (enable) {
      try {
        final ok = await LocalAuthentication().authenticate(
          localizedReason: 'Confirm your fingerprint to enable it for unlocking',
          options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
        );
        if (!ok) return;
      } on PlatformException catch (e) {
        if (mounted) showMessage(context, 'Fingerprint unavailable: ${e.message ?? e.code}', error: true);
        return;
      }
    }
    await _run(() => _auth.setBiometric(enable));
  }

  Future<void> _editUpi() async {
    final id = await promptText(context,
        title: 'Your UPI ID', label: 'e.g. name@okbank', initial: _upiId ?? '');
    if (id == null) return;
    if (id.trim().isNotEmpty && !id.contains('@')) {
      if (mounted) showMessage(context, 'A UPI ID looks like name@bank', error: true);
      return;
    }
    await _run(() => _settings.set(SettingsKeys.upiId, id.trim()));
  }

  Future<void> _editPayee() async {
    final name = await promptText(context,
        title: 'Payee name', label: 'Name shown in the UPI app', initial: _payee ?? '');
    if (name == null) return;
    await _run(() => _settings.set(SettingsKeys.upiPayeeName, name.trim()));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: const Center(child: CircularProgressIndicator()));
    }
    final user = _user;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          children: [
            if (_busy) const LinearProgressIndicator(),
            const _Header('Backup'),
            ListTile(
              leading: const Icon(Icons.backup),
              title: const Text('Export backup now'),
              subtitle: Text('Last backup: ${prettyStamp(_lastBackup)}'),
              onTap: _export,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('Weekly backup reminder'),
              subtitle: const Text('Shows a reminder on the home screen after 7 days'),
              value: _reminder,
              onChanged: (v) => _run(() => _settings.setBool(SettingsKeys.backupReminder, v)),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restore from backup'),
              subtitle: const Text('Replaces all data on this phone'),
              onTap: _restore,
            ),
            const _Header('Security'),
            ListTile(
              leading: const Icon(Icons.password),
              title: const Text('Change password'),
              subtitle: user == null ? null : Text('Signed in as ${user.username}'),
              onTap: _changePassword,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.pin),
              title: const Text('Quick-unlock PIN'),
              value: user?.hasPin ?? false,
              onChanged: _togglePin,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: const Text('Unlock with fingerprint'),
              subtitle: _biometricAvailable ? null : const Text('Not available on this phone'),
              value: user?.biometricEnabled ?? false,
              onChanged: _biometricAvailable ? _toggleBiometric : null,
            ),
            ListTile(
              leading: const Icon(Icons.lock),
              title: const Text('Lock app now'),
              onTap: () =>
                  Navigator.pushNamedAndRemoveUntil(context, Routes.login, (_) => false),
            ),
            const _Header('UPI payments'),
            ListTile(
              leading: const Icon(Icons.qr_code),
              title: const Text('UPI ID'),
              subtitle: Text(_upiId ?? 'Not set — needed for "Pay via UPI"'),
              onTap: _editUpi,
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Payee name'),
              subtitle: Text(_payee ?? 'Not set'),
              onTap: _editPayee,
            ),
            const _Header('About'),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Loan & Chit Manager'),
              subtitle: Text('Version 1.0.0 · all data is stored only on this phone. '
                  'UPI payments are confirmed manually; the app cannot verify them.'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_next.text != _confirm.text) {
      setState(() => _error = 'New passwords do not match');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService().changePassword(_current.text, _next.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password')),
          const SizedBox(height: 12),
          TextField(
              controller: _next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password (6+ characters)')),
          const SizedBox(height: 12),
          TextField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm new password')),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('Change password')),
      ],
    );
  }
}
