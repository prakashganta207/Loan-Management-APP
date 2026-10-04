import '../core/errors.dart';
import '../core/format.dart';

class ChitCalculation {
  const ChitCalculation({
    required this.chitValue,
    required this.members,
    required this.winningAmount,
    required this.commissionPercent,
    required this.discount,
    required this.commission,
    required this.dividendPool,
    required this.dividendPerMember,
    required this.baseContribution,
    required this.effectiveContribution,
  });

  final double chitValue;
  final int members;
  final double winningAmount;
  final double commissionPercent;
  final double discount;
  final double commission;
  final double dividendPool;
  final double dividendPerMember;

  /// chit value ÷ members, before dividend.
  final double baseContribution;

  /// What each member actually pays this month (base − dividend).
  final double effectiveContribution;
}

/// The one place chit maths lives — used by the calculator screen, the
/// auction preview and the auction service, so they can never disagree.
class ChitCalculator {
  static ChitCalculation calculate({
    required double chitValue,
    required int members,
    required double winningAmount,
    required double commissionPercent,
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
    final discount = round2(chitValue - winningAmount);
    final commission = round2(chitValue * commissionPercent / 100);
    final pool = round2(discount - commission);
    if (pool < -kEps) {
      throw ValidationException('Discount (${money(discount)}) is less than the commission '
          '(${money(commission)}). Winning amount can be at most ${money(chitValue - commission)}.');
    }
    final perMember = round2(pool / members);
    final base = round2(chitValue / members);
    return ChitCalculation(
      chitValue: chitValue,
      members: members,
      winningAmount: winningAmount,
      commissionPercent: commissionPercent,
      discount: discount,
      commission: commission,
      dividendPool: pool < 0 ? 0 : pool,
      dividendPerMember: perMember < 0 ? 0 : perMember,
      baseContribution: base,
      effectiveContribution: round2(base - (perMember < 0 ? 0 : perMember)),
    );
  }
}
