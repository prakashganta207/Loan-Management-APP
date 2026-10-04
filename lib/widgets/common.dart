import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/errors.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/chit_calculator.dart';
import '../services/upi_service.dart';

String errorText(Object e) => e is ValidationException ? e.message : 'Error: $e';

void showMessage(BuildContext context, String message, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? scheme.error : null,
      behavior: SnackBarBehavior.floating,
    ));
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error)
              : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Single-field text prompt. Returns null if cancelled.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  TextInputType keyboardType = TextInputType.text,
  bool obscure = false,
  String confirmLabel = 'Save',
}) {
  return showDialog<String>(
    context: context,
    builder: (c) => _PromptDialog(
      title: title,
      label: label,
      initial: initial,
      keyboardType: keyboardType,
      obscure: obscure,
      confirmLabel: confirmLabel,
    ),
  );
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.keyboardType,
    required this.obscure,
    required this.confirmLabel,
  });
  final String title;
  final String label;
  final String initial;
  final TextInputType keyboardType;
  final bool obscure;
  final String confirmLabel;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        obscureText: widget.obscure,
        keyboardType: widget.keyboardType,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _c.text), child: Text(widget.confirmLabel)),
      ],
    );
  }
}

/// FutureBuilder with consistent loading / error states.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.future, required this.builder, this.standalone = false});
  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;

  /// True when this is a route's root widget (builder returns a Scaffold),
  /// so loading/error states need their own Scaffold.
  final bool standalone;

  Widget _wrap(Widget child) => standalone ? Scaffold(appBar: AppBar(), body: child) : child;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) {
          return _wrap(Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load this screen.\n${errorText(snap.error!)}',
                  textAlign: TextAlign.center),
            ),
          ));
        }
        if (!snap.hasData) return _wrap(const Center(child: CircularProgressIndicator()));
        return builder(context, snap.data as T);
      },
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.subtitle,
    this.onTap,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 20, color: c),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      style: theme.textTheme.labelLarge, overflow: TextOverflow.ellipsis),
                ),
              ]),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700, color: c)),
              ),
              if (subtitle != null)
                Text(subtitle!, style: theme.textTheme.bodySmall, maxLines: 2),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays children out in 2 columns on phones, 4 on wide screens.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children, this.spacing = 10});
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth > 640 ? 4 : 2;
      final w = (box.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final c in children) SizedBox(width: w, child: c)],
      );
    });
  }
}

Color statusColor(String status) => switch (status) {
      'paid' || 'completed' => AppColors.paid,
      'partial' || 'pending' => AppColors.partial,
      'missed' => AppColors.missed,
      'active' => AppColors.info,
      _ => AppColors.neutral,
    };

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.label});
  final String status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    final text = label ?? (status.isEmpty ? status : status[0].toUpperCase() + status.substring(1));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withAlpha(30),
        border: Border.all(color: c),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.emphasize = false, this.color});
  final String label;
  final String value;
  final bool emphasize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasize
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color)
        : theme.textTheme.bodyLarge?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: 12),
          Flexible(child: Text(value, style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

/// "Commission paid by: Winner / Members" toggle (chit form and calculator).
class CommissionModeSelector extends StatelessWidget {
  const CommissionModeSelector({super.key, required this.value, this.onChanged});
  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Commission paid by', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: CommissionMode.fromWinner, label: Text('Winner')),
            ButtonSegment(value: CommissionMode.fromDividend, label: Text('Members')),
          ],
          selected: {value},
          onSelectionChanged:
              onChanged == null ? null : (s) => onChanged!(s.first),
        ),
        const SizedBox(height: 4),
        Text(
          value == CommissionMode.fromWinner
              ? 'Members pay auctioned price ÷ members; commission is deducted from the winner.'
              : 'Commission is deducted from the dividend; the winner gets the full amount.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// The auction split from [ChitCalculator], shown the same way everywhere.
class ChitSplitDetails extends StatelessWidget {
  const ChitSplitDetails(this.calc, {super.key, this.showBase = false});
  final ChitCalculation calc;
  final bool showBase;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      InfoRow('Commission paid by', CommissionMode.label(calc.commissionMode)),
      InfoRow('Discount', money(calc.discount)),
      InfoRow('Commission', money(calc.commission)),
      InfoRow('Dividend pool', money(calc.dividendPool)),
      InfoRow('Dividend per member', money(calc.dividendPerMember)),
      InfoRow('Winner receives', money(calc.winnerPayout), emphasize: true),
      const Divider(),
      if (showBase) InfoRow('Contribution before dividend', money(calc.baseContribution)),
      InfoRow('Each member pays', money(calc.effectiveContribution), emphasize: true),
      Align(
        alignment: Alignment.centerRight,
        child: Text(calc.memberPaymentFormula, style: Theme.of(context).textTheme.bodySmall),
      ),
    ]);
  }
}

/// Number input for rupee amounts.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.label,
    this.required = true,
    this.allowZero = false,
    this.onChanged,
    this.helperText,
  });
  final TextEditingController controller;
  final String label;
  final bool required;
  final bool allowZero;
  final ValueChanged<String>? onChanged;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(labelText: label, prefixText: '₹ ', helperText: helperText),
      onChanged: onChanged,
      validator: (v) {
        final text = v?.trim() ?? '';
        if (text.isEmpty) return required ? 'Required' : null;
        final n = parseAmount(text);
        if (n == null) return 'Enter a number';
        if (n < 0) return 'Cannot be negative';
        if (n == 0 && !allowZero) return 'Must be more than zero';
        return null;
      },
    );
  }
}

/// Whole-number input (days, months, members).
class CountField extends StatelessWidget {
  const CountField({
    super.key,
    required this.controller,
    required this.label,
    this.onChanged,
    this.helperText,
  });
  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, helperText: helperText),
      onChanged: onChanged,
      validator: (v) {
        final n = int.tryParse(v?.trim() ?? '');
        if (n == null) return 'Required';
        if (n <= 0) return 'Must be at least 1';
        return null;
      },
    );
  }
}

/// Tappable date picker field holding a `yyyy-MM-dd` value.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.helperText,
  });
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: parseDate(value),
          firstDate: firstDate ?? DateTime(2000),
          lastDate: lastDate ?? DateTime(2100),
        );
        if (picked != null) onChanged(dateKey(picked));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          suffixIcon: const Icon(Icons.calendar_today),
        ),
        child: Text(prettyDate(value)),
      ),
    );
  }
}

/// Opens the UPI app, then asks the lender to confirm manually.
/// Returns true only when the lender taps "Confirm paid".
Future<bool> runUpiFlow(BuildContext context, {required double amount, required String note}) async {
  final upi = UpiService();
  final cfg = await upi.config();
  if (!context.mounted) return false;
  if (cfg == null) {
    showMessage(context, 'Add your UPI ID in Settings first', error: true);
    return false;
  }
  final launched = await upi.launch(UpiService.buildUri(
      upiId: cfg.upiId, payeeName: cfg.payeeName, amount: amount, note: note));
  if (!context.mounted) return false;
  if (!launched) {
    showMessage(context, 'No UPI app found on this phone', error: true);
    return false;
  }
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: const Text('Did the payment go through?'),
      content: Text('Check that ${money(amount)} reached ${cfg.upiId} before confirming. '
          'The app cannot verify UPI payments automatically.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not yet')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirm paid')),
      ],
    ),
  );
  return ok ?? false;
}
