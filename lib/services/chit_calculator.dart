import '../core/errors.dart';
import '../core/format.dart';
import '../models/models.dart';

class ChitCalculation {
  const ChitCalculation({
    required this.chitValue,
    required this.members,
    required this.winningAmount,
    required this.commissionPercent,
    required this.commissionMode,
    required this.discount,
    required this.commission,
    required this.dividendPool,
    required this.dividendPerMember,
    required this.baseContribution,
    required this.effectiveContribution,
    required this.winnerPayout,
  });

  final double chitValue;
  final int members;
  final double winningAmount;
  final double commissionPercent;
  final String commissionMode;
  final double discount;
  final double commission;
  final double dividendPool;
  final double dividendPerMember;

  /// chit value ÷ members, before dividend.
  final double baseContribution;

  /// What each member actually pays this month.
  final double effectiveContribution;

  /// What the winner actually receives.
  final double winnerPayout;

  /// One-line working for the member payment, e.g. "₹80,000.00 ÷ 20 = ₹4,000.00".
  String get memberPaymentFormula => commissionMode == CommissionMode.fromWinner
      ? '${money(winningAmount)} ÷ $members = ${money(effectiveContribution)}'
      : '${money(baseContribution)} − ${money(dividendPerMember)} = '
          '${money(effectiveContribution)}';
}

/// The one place chit maths lives — used by the calculator screen, the
/// auction preview and the auction service, so they can never disagree.
class ChitCalculator {
  static ChitCalculation calculate({
    required double chitValue,
    required int members,
    required double winningAmount,
    required double commissionPercent,
    required String commissionMode,
  }) {
    if (chitValue <= 0) throw const ValidationException('Chit value must be more than zero');
    if (members <= 0) throw const ValidationException('Members must be at least 1');
    if (winningAmount <= 0) {
      throw const ValidationException('Winning amount must be more than zero');
    }
    if (winningAmount > chitValue + kEps) {
      throw const ValidationException('Winning amount cannot be more than the chit value');
    }
    if (commissionPercent < 0 || commissionPercent > 100) {
      throw const ValidationException('Commission must be between 0 and 100%');
    }
    if (!CommissionMode.all.contains(commissionMode)) {
      throw ValidationException('Unknown commission mode: $commissionMode');
    }
    final discount = round2(chitValue - winningAmount);
    final commission = round2(chitValue * commissionPercent / 100);
    final base = round2(chitValue / members);

    if (commissionMode == CommissionMode.fromWinner) {
      // Whole discount is shared; the winner bears the commission.
      final payout = round2(winningAmount - commission);
      if (payout <= 0) {
        throw ValidationException('Commission (${money(commission)}) leaves nothing for the '
            'winner. Winning amount must be more than ${money(commission)}.');
      }
      return ChitCalculation(
        chitValue: chitValue,
        members: members,
        winningAmount: winningAmount,
        commissionPercent: commissionPercent,
        commissionMode: commissionMode,
        discount: discount,
        commission: commission,
        dividendPool: discount,
        dividendPerMember: round2(discount / members),
        baseContribution: base,
        effectiveContribution: round2(winningAmount / members),
        winnerPayout: payout,
      );
    }

    // from_dividend: commission comes out of the discount before it is shared.
    final pool = round2(discount - commission);
    if (pool < -kEps) {
      throw ValidationException('Discount (${money(discount)}) is less than the commission '
          '(${money(commission)}). Winning amount can be at most ${money(chitValue - commission)}.');
    }
    final perMember = round2(pool / members);
    return ChitCalculation(
      chitValue: chitValue,
      members: members,
      winningAmount: winningAmount,
      commissionPercent: commissionPercent,
      commissionMode: commissionMode,
      discount: discount,
      commission: commission,
      dividendPool: pool < 0 ? 0 : pool,
      dividendPerMember: perMember < 0 ? 0 : perMember,
      baseContribution: base,
      effectiveContribution: round2(base - (perMember < 0 ? 0 : perMember)),
      winnerPayout: round2(winningAmount),
    );
  }
}
