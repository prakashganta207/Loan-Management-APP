import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../services/chit_calculator.dart';
import '../../widgets/common.dart';

/// Standalone what-if calculator. Nothing is saved.
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final _value = TextEditingController();
  final _members = TextEditingController();
  final _winning = TextEditingController();
  final _commission = TextEditingController(text: '5');

  @override
  void dispose() {
    for (final c in [_value, _members, _winning, _commission]) {
      c.dispose();
    }
    super.dispose();
  }

  (ChitCalculation?, String?) _compute() {
    final value = parseAmount(_value.text);
    final members = int.tryParse(_members.text.trim());
    final winning = parseAmount(_winning.text);
    final commission = parseAmount(_commission.text) ?? 0;
    if (value == null || members == null || winning == null) return (null, null);
    try {
      return (
        ChitCalculator.calculate(
            chitValue: value,
            members: members,
            winningAmount: winning,
            commissionPercent: commission),
        null
      );
    } catch (e) {
      return (null, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final (calc, error) = _compute();
    void changed(String _) => setState(() {});
    return Scaffold(
      appBar: AppBar(title: const Text('Chit calculator')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AmountField(controller: _value, label: 'Chit value', onChanged: changed),
          const SizedBox(height: 14),
          CountField(controller: _members, label: 'Number of members', onChanged: changed),
          const SizedBox(height: 14),
          AmountField(
              controller: _winning,
              label: 'Winning amount (taken by winner)',
              onChanged: changed),
          const SizedBox(height: 14),
          TextField(
            controller: _commission,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Commission', suffixText: '%'),
            onChanged: changed,
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: calc == null
                  ? Text(error ?? 'Fill in all four fields to see the split.',
                      style: TextStyle(
                          color: error == null ? null : Theme.of(context).colorScheme.error))
                  : Column(children: [
                      InfoRow('Discount', money(calc.discount)),
                      InfoRow('Commission', money(calc.commission)),
                      InfoRow('Dividend pool', money(calc.dividendPool)),
                      InfoRow('Dividend per member', money(calc.dividendPerMember)),
                      const Divider(),
                      InfoRow('Contribution before dividend', money(calc.baseContribution)),
                      InfoRow('Each member pays', money(calc.effectiveContribution),
                          emphasize: true),
                    ]),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Discount = value − winning amount. Commission = value × %. '
            'Dividend pool = discount − commission, shared equally by all members.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
