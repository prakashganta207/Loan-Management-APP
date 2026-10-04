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
    this.borrowerName,
  });

  final int? id;
  final int borrowerId;
  final String loanName;
  final double totalPayable;
  final double dailyPayment;
  final int durationDays;
  final double finePerDay;
  final String startDate;
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
  const PaymentRow({required this.payment, required this.loanName, required this.borrowerName});

  final LoanPayment payment;
  final String loanName;
  final String borrowerName;

  factory PaymentRow.fromMap(Map<String, Object?> m) => PaymentRow(
        payment: LoanPayment.fromMap(m),
        loanName: m['loan_name'] as String? ?? '',
        borrowerName: m['borrower_name'] as String? ?? '',
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
    required this.createdAt,
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
  final String createdAt;
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
        createdAt: m['created_at'] as String? ?? '',
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
