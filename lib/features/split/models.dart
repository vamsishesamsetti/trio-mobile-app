/// Models for the Splitwise feature. Hand-written, mapping to Postgres rows.
library;

double _toDouble(dynamic v) =>
    v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

enum SplitType { equal, exact, percent, shares }

SplitType splitTypeFrom(String s) =>
    SplitType.values.firstWhere((e) => e.name == s, orElse: () => SplitType.equal);

class Group {
  final String id;
  final String name;
  final String createdBy;
  final String defaultCurrency;

  const Group({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.defaultCurrency,
  });

  factory Group.fromMap(Map<String, dynamic> m) => Group(
        id: m['id'] as String,
        name: m['name'] as String,
        createdBy: m['created_by'] as String,
        defaultCurrency: (m['default_currency'] as String?) ?? 'USD',
      );
}

class GroupMember {
  final String id;
  final String groupId;
  final String? userId;
  final String? inviteEmail;
  final String role;
  final DateTime? createdAt;
  // Joined from profiles for display.
  final String? displayName;

  const GroupMember({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.inviteEmail,
    required this.role,
    this.createdAt,
    this.displayName,
  });

  /// Best label for the member (profile name, else email, else short id).
  String get label =>
      displayName ??
      inviteEmail ??
      (userId != null ? userId!.substring(0, 6) : 'Member');

  factory GroupMember.fromMap(Map<String, dynamic> m) {
    final profile = m['profiles'];
    return GroupMember(
      id: m['id'] as String,
      groupId: m['group_id'] as String,
      userId: m['user_id'] as String?,
      inviteEmail: m['invite_email'] as String?,
      role: (m['role'] as String?) ?? 'member',
      createdAt: m['created_at'] == null
          ? null
          : DateTime.parse(m['created_at'] as String).toLocal(),
      displayName:
          profile is Map<String, dynamic> ? profile['display_name'] as String? : null,
    );
  }

  GroupMember withDisplayName(String? name) => GroupMember(
        id: id,
        groupId: groupId,
        userId: userId,
        inviteEmail: inviteEmail,
        role: role,
        createdAt: createdAt,
        displayName: name ?? displayName,
      );
}

class ExpenseSplit {
  final String id;
  final String expenseId;
  final String userId;
  final double owedAmount;

  const ExpenseSplit({
    required this.id,
    required this.expenseId,
    required this.userId,
    required this.owedAmount,
  });

  factory ExpenseSplit.fromMap(Map<String, dynamic> m) => ExpenseSplit(
        id: m['id'] as String,
        expenseId: m['expense_id'] as String,
        userId: m['user_id'] as String,
        owedAmount: _toDouble(m['owed_amount']),
      );
}

class Expense {
  final String id;
  final String groupId;
  final String paidBy;
  final String description;
  final double amount;
  final String currency;
  final DateTime date;
  final SplitType splitType;
  final String? category;
  final DateTime createdAt;
  final String? receiptUrl;
  final DateTime? deletedAt;
  final String? deletedBy;
  final List<ExpenseSplit> splits;

  const Expense({
    required this.id,
    required this.groupId,
    required this.paidBy,
    required this.description,
    required this.amount,
    required this.currency,
    required this.date,
    required this.splitType,
    required this.category,
    required this.createdAt,
    this.receiptUrl,
    this.deletedAt,
    this.deletedBy,
    this.splits = const [],
  });

  bool get isDeleted => deletedAt != null;

  factory Expense.fromMap(Map<String, dynamic> m) {
    final rawSplits = (m['expense_splits'] as List?) ?? const [];
    return Expense(
      id: m['id'] as String,
      groupId: m['group_id'] as String,
      paidBy: m['paid_by'] as String,
      description: m['description'] as String,
      amount: _toDouble(m['amount']),
      currency: (m['currency'] as String?) ?? 'USD',
      date: DateTime.parse(m['expense_date'] as String),
      splitType: splitTypeFrom(m['split_type'] as String),
      category: m['category'] as String?,
      createdAt: m['created_at'] == null
          ? DateTime.parse(m['expense_date'] as String)
          : DateTime.parse(m['created_at'] as String).toLocal(),
      receiptUrl: m['receipt_url'] as String?,
      deletedAt: m['deleted_at'] == null
          ? null
          : DateTime.parse(m['deleted_at'] as String).toLocal(),
      deletedBy: m['deleted_by'] as String?,
      splits: rawSplits
          .map((e) => ExpenseSplit.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class Settlement {
  final String id;
  final String groupId;
  final String fromUser;
  final String toUser;
  final double amount;
  final DateTime settledAt;
  final DateTime? deletedAt;
  final String? deletedBy;

  const Settlement({
    required this.id,
    required this.groupId,
    required this.fromUser,
    required this.toUser,
    required this.amount,
    required this.settledAt,
    this.deletedAt,
    this.deletedBy,
  });

  bool get isDeleted => deletedAt != null;

  factory Settlement.fromMap(Map<String, dynamic> m) => Settlement(
        id: m['id'] as String,
        groupId: m['group_id'] as String,
        fromUser: m['from_user'] as String,
        toUser: m['to_user'] as String,
        amount: _toDouble(m['amount']),
        settledAt: DateTime.parse(m['settled_at'] as String).toLocal(),
        deletedAt: m['deleted_at'] == null
            ? null
            : DateTime.parse(m['deleted_at'] as String).toLocal(),
        deletedBy: m['deleted_by'] as String?,
      );
}

class ExpenseComment {
  final String id;
  final String expenseId;
  final String userId;
  final String body;
  final DateTime createdAt;
  final String? displayName; // resolved separately

  const ExpenseComment({
    required this.id,
    required this.expenseId,
    required this.userId,
    required this.body,
    required this.createdAt,
    this.displayName,
  });

  factory ExpenseComment.fromMap(Map<String, dynamic> m) => ExpenseComment(
        id: m['id'] as String,
        expenseId: m['expense_id'] as String,
        userId: m['user_id'] as String,
        body: m['body'] as String,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );

  ExpenseComment withDisplayName(String? name) => ExpenseComment(
        id: id,
        expenseId: expenseId,
        userId: userId,
        body: body,
        createdAt: createdAt,
        displayName: name ?? displayName,
      );
}
