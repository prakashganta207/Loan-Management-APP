import 'package:flutter_test/flutter_test.dart';
import 'package:loan_chit_manager/core/errors.dart';
import 'package:loan_chit_manager/services/chit_calculator.dart';
import 'package:loan_chit_manager/services/upi_service.dart';

void main() {
  group('ChitCalculator', () {
    test('standard auction split', () {
      final c = ChitCalculator.calculate(
          chitValue: 100000, members: 20, winningAmount: 80000, commissionPercent: 5);
      expect(c.discount, 20000);
      expect(c.commission, 5000);
      expect(c.dividendPool, 15000);
      expect(c.dividendPerMember, 750);
      expect(c.baseContribution, 5000);
      expect(c.effectiveContribution, 4250);
    });

    test('zero commission gives whole discount to members', () {
      final c = ChitCalculator.calculate(
          chitValue: 50000, members: 10, winningAmount: 45000, commissionPercent: 0);
      expect(c.dividendPool, 5000);
      expect(c.effectiveContribution, 4500);
    });

    test('rejects winning amount above chit value', () {
      expect(
          () => ChitCalculator.calculate(
              chitValue: 100000, members: 20, winningAmount: 100001, commissionPercent: 5),
          throwsA(isA<ValidationException>()));
    });

    test('rejects a discount smaller than the commission', () {
      expect(
          () => ChitCalculator.calculate(
              chitValue: 100000, members: 20, winningAmount: 98000, commissionPercent: 5),
          throwsA(isA<ValidationException>()));
    });
  });

  test('UPI link is built and encoded correctly', () {
    final uri = UpiService.buildUri(
        upiId: 'ravi@okbank', payeeName: 'Ravi Kumar', amount: 300, note: 'Shop loan');
    expect(uri.toString(),
        'upi://pay?pa=ravi%40okbank&pn=Ravi%20Kumar&am=300.00&cu=INR&tn=Shop%20loan');
  });
}
