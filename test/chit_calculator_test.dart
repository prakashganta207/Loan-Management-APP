import 'package:flutter_test/flutter_test.dart';
import 'package:loan_chit_manager/core/errors.dart';
import 'package:loan_chit_manager/models/models.dart';
import 'package:loan_chit_manager/services/chit_calculator.dart';
import 'package:loan_chit_manager/services/upi_service.dart';

void main() {
  group('ChitCalculator', () {
    test('standard auction split', () {
      final c = ChitCalculator.calculate(
          chitValue: 100000, members: 20, winningAmount: 80000, commissionPercent: 5, commissionMode: CommissionMode.fromDividend);
      expect(c.discount, 20000);
      expect(c.commission, 5000);
      expect(c.dividendPool, 15000);
      expect(c.dividendPerMember, 750);
      expect(c.baseContribution, 5000);
      expect(c.effectiveContribution, 4250);
    });

    test('zero commission gives whole discount to members', () {
      final c = ChitCalculator.calculate(
          chitValue: 50000, members: 10, winningAmount: 45000, commissionPercent: 0, commissionMode: CommissionMode.fromDividend);
      expect(c.dividendPool, 5000);
      expect(c.effectiveContribution, 4500);
    });

    test('rejects winning amount above chit value', () {
      expect(
          () => ChitCalculator.calculate(
              chitValue: 100000, members: 20, winningAmount: 100001, commissionPercent: 5, commissionMode: CommissionMode.fromDividend),
          throwsA(isA<ValidationException>()));
    });

    test('rejects a discount smaller than the commission', () {
      expect(
          () => ChitCalculator.calculate(
              chitValue: 100000, members: 20, winningAmount: 98000, commissionPercent: 5, commissionMode: CommissionMode.fromDividend),
          throwsA(isA<ValidationException>()));
    });
  });

  group('ChitCalculator commission modes (100000, 20 members, won at 80000, 5%)', () {
    ChitCalculation calc(String mode, {double commission = 5, double winning = 80000}) =>
        ChitCalculator.calculate(
            chitValue: 100000,
            members: 20,
            winningAmount: winning,
            commissionPercent: commission,
            commissionMode: mode);

    test('from_dividend: members bear the commission, winner gets the full amount', () {
      final c = calc(CommissionMode.fromDividend);
      expect(c.commission, 5000);
      expect(c.dividendPerMember, 750);
      expect(c.effectiveContribution, 4250);
      expect(c.winnerPayout, 80000);
      expect(c.memberPaymentFormula, '₹5,000.00 − ₹750.00 = ₹4,250.00');
    });

    test('from_winner: whole discount is shared, winner bears the commission', () {
      final c = calc(CommissionMode.fromWinner);
      expect(c.discount, 20000);
      expect(c.commission, 5000);
      expect(c.dividendPool, 20000);
      expect(c.dividendPerMember, 1000);
      expect(c.baseContribution, 5000);
      expect(c.effectiveContribution, 4000);
      expect(c.winnerPayout, 75000);
      expect(c.memberPaymentFormula, '₹80,000.00 ÷ 20 = ₹4,000.00');
    });

    test('from_winner: members pay exactly winning amount ÷ members', () {
      final c = calc(CommissionMode.fromWinner, winning: 77777);
      expect(c.effectiveContribution, 3888.85); // 77777 / 20
      expect(c.winnerPayout, 72777);
    });

    test('with 0% commission both modes give the same split', () {
      for (final winning in [80000.0, 95000.0, 60000.0]) {
        final a = calc(CommissionMode.fromWinner, commission: 0, winning: winning);
        final b = calc(CommissionMode.fromDividend, commission: 0, winning: winning);
        expect(a.discount, b.discount);
        expect(a.commission, b.commission);
        expect(a.dividendPool, b.dividendPool);
        expect(a.dividendPerMember, b.dividendPerMember);
        expect(a.effectiveContribution, b.effectiveContribution);
        expect(a.winnerPayout, b.winnerPayout);
      }
    });

    test('with 0% commission and an uneven split the modes differ by at most a paisa', () {
      // from_winner rounds winning ÷ members once; from_dividend rounds base and
      // dividend separately, so 80000 ÷ 3 can land 1 paisa apart.
      final a = ChitCalculator.calculate(
          chitValue: 100000, members: 3, winningAmount: 80000, commissionPercent: 0,
          commissionMode: CommissionMode.fromWinner);
      final b = ChitCalculator.calculate(
          chitValue: 100000, members: 3, winningAmount: 80000, commissionPercent: 0,
          commissionMode: CommissionMode.fromDividend);
      expect(a.dividendPerMember, b.dividendPerMember);
      expect(a.winnerPayout, b.winnerPayout);
      expect((a.effectiveContribution - b.effectiveContribution).abs(), lessThanOrEqualTo(0.01));
    });

    test('from_winner allows a discount smaller than the commission', () {
      final c = calc(CommissionMode.fromWinner, winning: 98000);
      expect(c.dividendPerMember, 100);
      expect(c.effectiveContribution, 4900);
      expect(c.winnerPayout, 93000);
    });

    test('from_winner rejects a commission that leaves the winner nothing', () {
      expect(() => calc(CommissionMode.fromWinner, commission: 80),
          throwsA(isA<ValidationException>())); // payout 80000 − 80000 = 0
      expect(() => calc(CommissionMode.fromWinner, commission: 100),
          throwsA(isA<ValidationException>()));
    });

    test('rejects an unknown commission mode', () {
      expect(() => calc('from_nobody'), throwsA(isA<ValidationException>()));
    });
  });

  test('UPI link is built and encoded correctly', () {
    final uri = UpiService.buildUri(
        upiId: 'ravi@okbank', payeeName: 'Ravi Kumar', amount: 300, note: 'Shop loan');
    expect(uri.toString(),
        'upi://pay?pa=ravi%40okbank&pn=Ravi%20Kumar&am=300.00&cu=INR&tn=Shop%20loan');
  });
}
