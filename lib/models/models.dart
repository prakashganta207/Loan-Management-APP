import '../core/format.dart';

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
double? _dn(Object? v) => (v as num?)?.toDouble();
int _i(Object? v) => (v as num?)?.toInt() ?? 0;

/// Shared by loans and chit groups: active → completed → archived.
class RecordStatus {
  static const active = 'active';
  static const completed = 'completed';
  static const archived = 'archived';
  static const all = [active, completed, archived];

  /// The only status each one may move to next.
  static String? next(String current) => switch (current) {
        RecordStatus.active => RecordStatus.completed,
        RecordStatus.completed => RecordStatus.archived,
        _ => null,
      };
}

/// How a loan is repaid. Monthly loans reuse `daily_payment` for the monthly
/// instalment and `duration_days` for the number of months (see SPEC.md).
class RepaymentType {
  static const daily = 'daily';
  static const monthly = 'monthly';
  static const all = [daily, monthly];
}

/// Where a chit auction's winner stands in the "set up a loan" queue.
class LoanSetupStatus {
  static const pending = 'pending';
  static const created = 'created';
  static const dismissed = 'dismissed';

  static String label(String s) => switch (s) {
        created => 'Loan created',
        dismissed => 'Dismissed',
        _ => 'Waiting for setup',
      };
}

class PaymentStatus {
  static const paid = 'paid';
  static const missed = 'missed';
  static const partial = 'partial';
}

class MemberStatus {
  static const active = 'active';
  static const inactive = 'inactive';
}

class ContributionStatus {
  static const paid = 'paid';
  static const pending = 'pending';
}

/// Who bears the organizer's commission in a chit auction.
class CommissionMode {
  /// Commission comes out of the dividend; the winner gets the full winning amount.
  static const fromDividend = 'from_dividend';

  /// Whole discount is the dividend; commission is deducted from the winner's prize.
  static const fromWinner = 'from_winner';
  static const all = [fromWinner, fromDividend];

  static String label(String mode) =>
      mode == fromWinner ? 'Paid by winner' : 'Deducted from dividend';
}

class Borrower {
  const Borrower({
    this.id,
    required this.name,
    this.phone,
    this.address,
    this.notes,
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final String? phone;
  final String? address;
  final String? notes;
  final bool isArchived;
  final String createdAt;
  final String updatedAt;

  factory Borrower.fromMap(Map<String, Object?> m) => Borrower(
        id: m['id'] as int?,
        name: m['name'] as String? ?? '',
        phone: m['phone'] as String?,
        address: m['address'] as String?,
        notes: m['notes'] as String?,
        isArchived: _i(m['is_archived']) == 1,
        createdAt: m['created_at'] as String? ?? '',
        updatedAt: m['updated_at'] as String? ?? '',
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'notes': notes,
        'is_archived': isArchived ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  Borrower copyWith({String? name, String? phone, String? address, String? notes}) =>
      Borrower(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        address: address ?? this.address,
        notes: notes ?? this.notes,
        isArchived: isArchived,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

class Loan {
  const Loan({
    this.id,
    required this.borrowerId,
    required this.loanName,
    required this.totalPayable,
    required this.dailyPayment,
    required this.durationDays,
    required this.finePerDay,
    required this.startDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.repaymentType = RepaymentType.daily,
    this.lateInterestPercent = 0,
    this.graceDays = 0,
    this.sourceChitAuctionId,
    this.borrowerName,
  });

  final int? id;
  final int borrowerId;
  final String loanName;
  final double totalPayable;

  /// DB column `daily_payment`: the instalment (per day, or per month for monthly
  /// loans). Prefer [installmentAmount] in new code.
  final double dailyPayment;

  /// DB column `duration_days`: number of instalments (days, or months for monthly
  /// loans). Prefer [installmentCount] in new code.
  final int durationDays;
  final double finePerDay;
  final String startDate;
  final String repaymentType;

  /// Monthly loans: simple interest per month on an overdue instalment.
  final double lateInterestPercent;

  /// Monthly loans: days after the due date before late interest starts.
  final int graceDays;

  /// Set when the loan was created for a chit auction winner.
  final int? sourceChitAuctionId;

  bool get isMonthly => repaymentType == RepaymentType.monthly;
  double get installmentAmount => dailyPayment;
  int get installmentCount => durationDays;

  /// "day" or "month" — for labels like "₹300 / day".
  String get periodLabel => isMonthly ? 'month' : 'day';
  final String status;
  final String createdAt;
  final String updatedAt;

  /// Filled when the query joins `borrowers`.
  final String? borrowerName;

  factory Loan.fromMap(Map<String, Object?> m) => Loan(
        id: m['id'] as int?,
        borrowerId: _i(m['borrower_id']),
        loanName: m['loan_name'] as String? ?? '',
        totalPayable: _d(m['total_payable']),
        dailyPayment: _d(m['daily_payment']),
        durationDays: _i(m['duration_days']),
        finePerDay: _d(m['fine_per_day']),
        startDate: m['start_date'] as String? ?? '',
        status: m['status'] as String? ?? RecordStatus.active,
        createdAt: m['created_at'] as String? ?? '',
        updatedAt: m['updated_at'] as String? ?? '',
        repaymentType: m['repayment_type'] as String? ?? RepaymentType.daily,
        lateInterestPercent: _d(m['late_interest_percent']),
        graceDays: _i(m['grace_days']),
        sourceChitAuctionId: m['source_chit_auction_id'] as int?,
        borrowerName: m['borrower_name'] as String?,
      );
}

class LoanPayment {
  const LoanPayment({
    this.id,
    required this.loanId,
    required this.paymentDate,
    required this.scheduledAmount,
    required this.amountPaid,
    required this.fineAmount,
    required this.status,
    this.note,
    required this.createdAt,
  });

  final int? id;
  final int loanId;

  /// The schedule date (slot) this row covers.
  final String paymentDate;
  final double scheduledAmount;
  final double amountPaid;
  final double fineAmount;
  final String status;
  final String? note;

  /// When the money was actually collected / the row was written.
  final String createdAt;

  factory LoanPayment.fromMap(Map<String, Object?> m) => LoanPayment(
        id: m['id'] as int?,
        loanId: _i(m['loan_id']),
        paymentDate: m['payment_date'] as String? ?? '',
        scheduledAmount: _d(m['scheduled_amount']),
        amountPaid: _d(m['amount_paid']),
        fineAmount: _d(m['fine_amount']),
        status: m['status'] as String? ?? PaymentStatus.paid,
        note: m['note'] as String?,
        createdAt: m['created_at'] as String? ?? '',
      );
}

/// A payment row joined with its loan and borrower names (history/report lists).
class PaymentRow {
  const PaymentRow({
    required this.payment,
    required this.loanName,
    required this.borrowerName,
    this.repaymentType = RepaymentType.daily,
  });

  final LoanPayment payment;
  final String loanName;
  final String borrowerName;
  final String repaymentType;

  factory PaymentRow.fromMap(Map<String, Object?> m) => PaymentRow(
        payment: LoanPayment.fromMap(m),
        loanName: m['loan_name'] as String? ?? '',
        borrowerName: m['borrower_name'] as String? ?? '',
        repaymentType: m['repayment_type'] as String? ?? RepaymentType.daily,
      );
}

/// Derived loan figures — always computed from the ledger, never stored.
class LoanSummary {
  const LoanSummary({
    required this.loan,
    required this.totalPaid,
    required this.totalFine,
    required this.outstanding,
    required this.nextDueDate,
    required this.coveredDays,
    required this.daysRemaining,
    required this.overdueDays,
    this.overdueInstallments = 0,
    this.accruedLateCharge = 0,
    this.paidBySlot = const {},
  });

  final Loan loan;
  final double totalPaid;
  final double totalFine;
  final double outstanding;

  /// First schedule slot not yet fully paid (null when cleared).
  final String? nextDueDate;
  final int coveredDays;

  /// Daily payments still needed to clear the outstanding balance.
  final int daysRemaining;

  /// How many days the next due slot is behind today (0 if on time/ahead).
  final int overdueDays;

  /// Instalments whose due date is before today and that are not fully paid.
  final int overdueInstallments;

  /// Monthly loans: late interest built up on overdue instalments as of today
  /// (not charged yet — it is charged when the late payment is recorded).
  final double accruedLateCharge;

  /// Amount paid per schedule date (`yyyy-MM-dd` → ₹).
  final Map<String, double> paidBySlot;

  /// What is still unpaid on the instalment due on [slot].
  double unpaidOn(String slot) {
    final left = round2(loan.installmentAmount - (paidBySlot[slot] ?? 0));
    return left < 0 ? 0 : left;
  }

  bool get isCleared => outstanding <= kEps;
}

class ChitGroup {
  const ChitGroup({
    this.id,
    required this.chitName,
    this.chitValue,
    required this.numberOfMembers,
    required this.durationMonths,
    required this.commissionPercent,
    required this.commissionMode,
    required this.startDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String chitName;
  final double? chitValue;
  final int numberOfMembers;
  final int durationMonths;
  final double commissionPercent;
  final String commissionMode;
  final String startDate;
  final String status;
  final String createdAt;
  final String updatedAt;

  factory ChitGroup.fromMap(Map<String, Object?> m) => ChitGroup(
        id: m['id'] as int?,
        chitName: m['chit_name'] as String? ?? '',
        chitValue: _dn(m['chit_value']),
        numberOfMembers: _i(m['number_of_members']),
        durationMonths: _i(m['duration_months']),
        commissionPercent: _d(m['commission_percent']),
        commissionMode: m['commission_mode'] as String? ?? CommissionMode.fromDividend,
        startDate: m['start_date'] as String? ?? '',
        status: m['status'] as String? ?? RecordStatus.active,
        createdAt: m['created_at'] as String? ?? '',
        updatedAt: m['updated_at'] as String? ?? '',
      );
}

class ChitMember {
  const ChitMember({
    this.id,
    required this.chitGroupId,
    required this.memberName,
    this.phone,
    required this.membershipStatus,
    required this.hasWon,
    required this.joinedAt,
  });

  final int? id;
  final int chitGroupId;
  final String memberName;
  final String? phone;
  final String membershipStatus;
  final bool hasWon;
  final String joinedAt;

  factory ChitMember.fromMap(Map<String, Object?> m) => ChitMember(
        id: m['id'] as int?,
        chitGroupId: _i(m['chit_group_id']),
        memberName: m['member_name'] as String? ?? '',
        phone: m['phone'] as String?,
        membershipStatus: m['membership_status'] as String? ?? MemberStatus.active,
        hasWon: _i(m['has_won']) == 1,
        joinedAt: m['joined_at'] as String? ?? '',
      );
}

class ChitAuction {
  const ChitAuction({
    this.id,
    required this.chitGroupId,
    required this.monthNumber,
    required this.auctionDate,
    required this.winnerMemberId,
    required this.winningAmount,
    required this.discount,
    required this.commissionAmount,
    required this.dividendPool,
    required this.dividendPerMember,
    required this.winnerPayout,
    required this.createdAt,
    this.loanSetupStatus = LoanSetupStatus.pending,
    this.loanId,
    this.winnerName,
  });

  final int? id;
  final int chitGroupId;
  final int monthNumber;
  final String auctionDate;
  final int winnerMemberId;
  final double winningAmount;
  final double discount;
  final double commissionAmount;
  final double dividendPool;
  final double dividendPerMember;

  /// What the winner actually receives (winning amount, minus commission in from_winner mode).
  final double winnerPayout;
  final String createdAt;

  /// Whether a loan was set up for the winner (pending / created / dismissed).
  final String loanSetupStatus;
  final int? loanId;
  final String? winnerName;

  factory ChitAuction.fromMap(Map<String, Object?> m) => ChitAuction(
        id: m['id'] as int?,
        chitGroupId: _i(m['chit_group_id']),
        monthNumber: _i(m['month_number']),
        auctionDate: m['auction_date'] as String? ?? '',
        winnerMemberId: _i(m['winner_member_id']),
        winningAmount: _d(m['winning_amount']),
        discount: _d(m['discount']),
        commissionAmount: _d(m['commission_amount']),
        dividendPool: _d(m['dividend_pool']),
        dividendPerMember: _d(m['dividend_per_member']),
        winnerPayout: _d(m['winner_payout'] ?? m['winning_amount']),
        createdAt: m['created_at'] as String? ?? '',
        loanSetupStatus: m['loan_setup_status'] as String? ?? LoanSetupStatus.pending,
        loanId: m['loan_id'] as int?,
        winnerName: m['winner_name'] as String?,
      );
}

class ChitContribution {
  const ChitContribution({
    this.id,
    required this.chitGroupId,
    required this.chitMemberId,
    required this.monthNumber,
    required this.amount,
    required this.status,
    this.paymentDate,
    required this.createdAt,
    this.memberName,
  });

  final int? id;
  final int chitGroupId;
  final int chitMemberId;
  final int monthNumber;
  final double amount;
  final String status;
  final String? paymentDate;
  final String createdAt;
  final String? memberName;

  bool get isPaid => status == ContributionStatus.paid;

  factory ChitContribution.fromMap(Map<String, Object?> m) => ChitContribution(
        id: m['id'] as int?,
        chitGroupId: _i(m['chit_group_id']),
        chitMemberId: _i(m['chit_member_id']),
        monthNumber: _i(m['month_number']),
        amount: _d(m['amount']),
        status: m['status'] as String? ?? ContributionStatus.pending,
        paymentDate: m['payment_date'] as String?,
        createdAt: m['created_at'] as String? ?? '',
        memberName: m['member_name'] as String?,
      );
}

class ChitSummary {
  const ChitSummary({
    required this.group,
    required this.memberCount,
    required this.currentMonth,
    required this.auctionsDone,
    required this.totalCommission,
    required this.totalDividends,
  });

  final ChitGroup group;
  final int memberCount;
  final int currentMonth;
  final int auctionsDone;
  final double totalCommission;
  final double totalDividends;

  bool get isFull => memberCount >= group.numberOfMembers;
}

/// A chit auction winner in the "set up a loan" queue (Loans screen).
class ChitLoanItem {
  const ChitLoanItem({
    required this.auctionId,
    required this.chitId,
    required this.chitName,
    required this.monthNumber,
    required this.auctionDate,
    required this.memberId,
    required this.memberName,
    this.memberPhone,
    required this.prize,
    required this.status,
    this.loanId,
  });

  final int auctionId;
  final int chitId;
  final String chitName;
  final int monthNumber;
  final String auctionDate;
  final int memberId;
  final String memberName;
  final String? memberPhone;

  /// What the winner received: winner payout, or the winning amount for old rows.
  final double prize;
  final String status;
  final int? loanId;

  factory ChitLoanItem.fromMap(Map<String, Object?> m) => ChitLoanItem(
        auctionId: _i(m['auction_id']),
        chitId: _i(m['chit_group_id']),
        chitName: m['chit_name'] as String? ?? '',
        monthNumber: _i(m['month_number']),
        auctionDate: m['auction_date'] as String? ?? '',
        memberId: _i(m['winner_member_id']),
        memberName: m['member_name'] as String? ?? '',
        memberPhone: m['phone'] as String?,
        prize: _d(m['winner_payout'] ?? m['winning_amount']),
        status: m['loan_setup_status'] as String? ?? LoanSetupStatus.pending,
        loanId: m['loan_id'] as int?,
      );
}
