import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/routes.dart';
import '../../services/auth_service.dart';
import '../../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _pin = TextEditingController();

  AppUser? _user;
  bool _loading = true;
  bool _busy = false;
  bool _usePin = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = await _auth.currentUser();
    if (!mounted) return;
    setState(() {
      _user = user;
      _loading = false;
      _usePin = user?.hasPin ?? false;
      _password.clear();
      _pin.clear();
    });
    if (user != null && user.biometricEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _biometric());
    }
  }

  void _enter() => Navigator.pushReplacementNamed(context, Routes.dashboard);

  Future<void> _setup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await _auth.createUser(
        username: _username.text,
        password: _password.text,
        pin: _pin.text.trim().isEmpty ? null : _pin.text.trim(),
      );
      if (mounted) _enter();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlock() async {
    final secret = _usePin ? _pin.text.trim() : _password.text;
    if (secret.isEmpty) return;
    setState(() => _busy = true);
    final ok = _usePin ? await _auth.verifyPin(secret) : await _auth.verifyPassword(secret);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _enter();
    } else {
      showMessage(context, _usePin ? 'Wrong PIN' : 'Wrong password', error: true);
    }
  }

  Future<void> _biometric() async {
    final la = LocalAuthentication();
    try {
      if (!await la.isDeviceSupported()) return;
      final ok = await la.authenticate(
        localizedReason: 'Unlock Loan & Chit Manager',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (ok && mounted) _enter();
    } on PlatformException catch (e) {
      if (mounted) showMessage(context, 'Fingerprint unavailable: ${e.message ?? e.code}');
    }
  }

  Future<void> _forgot() async {
    final first = await confirmAction(
      context,
      title: 'Reset login?',
      message: 'This removes your password, PIN and fingerprint setting so you can create new '
          'ones. Your borrowers, loans and chits are NOT deleted.',
      confirmLabel: 'Continue',
    );
    if (!first || !mounted) return;
    final second = await confirmAction(
      context,
      title: 'Are you sure?',
      message: 'Anyone holding this phone will be able to set a new password and open your records.',
      confirmLabel: 'Reset login',
      destructive: true,
    );
    if (!second) return;
    await _auth.resetAuth();
    setState(() => _loading = true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final isSetup = _user == null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.menu_book_rounded, size: 64, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      isSetup ? 'Set up your account' : 'Welcome back, ${_user!.username}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isSetup
                          ? 'Your records stay on this phone. This password protects them.'
                          : 'Unlock to see today\'s collections.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    if (isSetup) ..._setupFields() else ..._unlockFields(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _passwordField(TextEditingController c, String label, {String? Function(String?)? validator}) {
    return TextFormField(
      controller: c,
      obscureText: _obscure,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      validator: validator,
      onFieldSubmitted: _user == null ? null : (_) => _unlock(),
    );
  }

  List<Widget> _setupFields() => [
        TextFormField(
          controller: _username,
          decoration: const InputDecoration(labelText: 'Your name'),
          textCapitalization: TextCapitalization.words,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 14),
        _passwordField(_password, 'Password',
            validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null),
        const SizedBox(height: 14),
        _passwordField(_confirm, 'Confirm password',
            validator: (v) => v != _password.text ? 'Passwords do not match' : null),
        const SizedBox(height: 14),
        TextFormField(
          controller: _pin,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Quick-unlock PIN (optional)',
            helperText: '4–6 digits. You can add it later in Settings.',
          ),
          validator: (v) {
            final t = v?.trim() ?? '';
            if (t.isEmpty) return null;
            return t.length < 4 ? 'At least 4 digits' : null;
          },
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _setup,
          child: _busy
              ? const SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create account'),
        ),
      ];

  List<Widget> _unlockFields() => [
        if (_usePin)
          TextField(
            controller: _pin,
            autofocus: true,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 8),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'PIN', counterText: ''),
            onSubmitted: (_) => _unlock(),
          )
        else
          _passwordField(_password, 'Password'),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _unlock,
          child: _busy
              ? const SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Unlock'),
        ),
        if (_user!.biometricEnabled) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _biometric,
            icon: const Icon(Icons.fingerprint),
            label: const Text('Use fingerprint'),
          ),
        ],
        const SizedBox(height: 8),
        if (_user!.hasPin)
          TextButton(
            onPressed: () => setState(() => _usePin = !_usePin),
            child: Text(_usePin ? 'Use password instead' : 'Use PIN instead'),
          ),
        TextButton(onPressed: _forgot, child: const Text('Forgot password?')),
      ];
}
