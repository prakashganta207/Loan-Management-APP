import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// One ledger row: schedule date, amounts, fine, status, when it was recorded.
class PaymentHistoryTile extends StatelessWidget {
  const PaymentHistoryTile(this.payment, {super.key, this.loanName});
  final LoanPayment payment;
  final String? loanName;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final parts = <String>[
      if (loanName != null) loanName!,
      'Scheduled ${money(p.scheduledAmount)}',
      if (p.fineAmount > 0) 'Fine ${money(p.fineAmount)}',
      'Recorded ${prettyStamp(p.createdAt)}',
      if (p.note != null) p.note!,
    ];
    return ListTile(
      dense: true,
      title: Text(
        p.status == PaymentStatus.missed
            ? '${prettyDate(p.paymentDate)} · nothing paid'
            : '${prettyDate(p.paymentDate)} · ${money(p.amountPaid)}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(parts.join(' · ')),
      trailing: StatusChip(p.status),
    );
  }
}
