/// Plain immutable models for the Money Tracker. Hand-written (no codegen) so
/// the build stays simple. Each maps to a Supabase/Postgres row.
library;

enum TxnType { income, expense, transfer }

TxnType _txnType(String s) =>
    TxnType.values.firstWhere((e) => e.name == s, orElse: () => TxnType.expense);

double _toDouble(dynamic v) =>
    v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

class Account {
  final String id;
  final String name;
  final String type;
  final double openingBalance;
  final String currency;
  final String? icon;
  final String? color;
  final bool archived;

  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.openingBalance,
    required this.currency,
    this.icon,
    this.color,
    this.archived = false,
  });

  factory Account.fromMap(Map<String, dynamic> m) => Account(
        id: m['id'] as String,
        name: m['name'] as String,
        type: (m['type'] as String?) ?? 'cash',
        openingBalance: _toDouble(m['opening_balance']),
        currency: (m['currency'] as String?) ?? 'USD',
        icon: m['icon'] as String?,
        color: m['color'] as String?,
        archived: (m['archived'] as bool?) ?? false,
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        'name': name,
        'type': type,
        'opening_balance': openingBalance,
        'currency': currency,
        'icon': icon,
        'color': color,
        'archived': archived,
      };

  Account copyWith({
    String? name,
    String? type,
    double? openingBalance,
    String? currency,
    String? icon,
    String? color,
    bool? archived,
  }) =>
      Account(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        openingBalance: openingBalance ?? this.openingBalance,
        currency: currency ?? this.currency,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        archived: archived ?? this.archived,
      );
}

class Category {
  final String id;
  final String name;
  final TxnType kind; // income or expense only
  final String? icon;
  final String? color;
  final String? parentId;

  const Category({
    required this.id,
    required this.name,
    required this.kind,
    this.icon,
    this.color,
    this.parentId,
  });

  bool get isExpense => kind == TxnType.expense;

  factory Category.fromMap(Map<String, dynamic> m) => Category(
        id: m['id'] as String,
        name: m['name'] as String,
        kind: _txnType(m['kind'] as String),
        icon: m['icon'] as String?,
        color: m['color'] as String?,
        parentId: m['parent_id'] as String?,
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        'name': name,
        'kind': kind.name,
        'icon': icon,
        'color': color,
        'parent_id': parentId,
      };

  Category copyWith({String? name, String? icon, String? color}) => Category(
        id: id,
        name: name ?? this.name,
        kind: kind,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        parentId: parentId,
      );
}

class MoneyTransaction {
  final String id;
  final String accountId;
  final String? categoryId;
  final TxnType type;
  final double amount;
  final String currency;
  final DateTime date;
  final String? note;
  final String? transferAccountId;

  const MoneyTransaction({
    required this.id,
    required this.accountId,
    required this.categoryId,
    required this.type,
    required this.amount,
    required this.currency,
    required this.date,
    this.note,
    this.transferAccountId,
  });

  factory MoneyTransaction.fromMap(Map<String, dynamic> m) => MoneyTransaction(
        id: m['id'] as String,
        accountId: m['account_id'] as String,
        categoryId: m['category_id'] as String?,
        type: _txnType(m['type'] as String),
        amount: _toDouble(m['amount']),
        currency: (m['currency'] as String?) ?? 'USD',
        date: DateTime.parse(m['txn_date'] as String),
        note: m['note'] as String?,
        transferAccountId: m['transfer_account_id'] as String?,
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        'account_id': accountId,
        'category_id': categoryId,
        'type': type.name,
        'amount': amount,
        'currency': currency,
        'txn_date': date.toIso8601String().split('T').first,
        'note': note,
        'transfer_account_id': transferAccountId,
      };

  MoneyTransaction copyWith({
    String? accountId,
    String? categoryId,
    TxnType? type,
    double? amount,
    DateTime? date,
    String? note,
    String? transferAccountId,
  }) =>
      MoneyTransaction(
        id: id,
        accountId: accountId ?? this.accountId,
        categoryId: categoryId ?? this.categoryId,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        currency: currency,
        date: date ?? this.date,
        note: note ?? this.note,
        transferAccountId: transferAccountId ?? this.transferAccountId,
      );
}

enum BudgetPeriod { weekly, monthly, yearly }

class Budget {
  final String id;
  final String categoryId;
  final double amount;
  final BudgetPeriod period;
  final DateTime startDate;

  const Budget({
    required this.id,
    required this.categoryId,
    required this.amount,
    required this.period,
    required this.startDate,
  });

  factory Budget.fromMap(Map<String, dynamic> m) => Budget(
        id: m['id'] as String,
        categoryId: m['category_id'] as String,
        amount: _toDouble(m['amount']),
        period: BudgetPeriod.values.firstWhere(
            (e) => e.name == m['period'],
            orElse: () => BudgetPeriod.monthly),
        startDate: DateTime.parse(m['start_date'] as String),
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        'category_id': categoryId,
        'amount': amount,
        'period': period.name,
        'start_date': startDate.toIso8601String().split('T').first,
      };
}

enum Frequency { daily, weekly, monthly, yearly }

class RecurringRule {
  final String id;
  final String accountId;
  final String? categoryId;
  final TxnType type;
  final double amount;
  final String? note;
  final Frequency frequency;
  final DateTime nextRunDate;

  const RecurringRule({
    required this.id,
    required this.accountId,
    required this.categoryId,
    required this.type,
    required this.amount,
    required this.note,
    required this.frequency,
    required this.nextRunDate,
  });

  factory RecurringRule.fromMap(Map<String, dynamic> m) => RecurringRule(
        id: m['id'] as String,
        accountId: m['account_id'] as String,
        categoryId: m['category_id'] as String?,
        type: _txnType(m['type'] as String),
        amount: _toDouble(m['amount']),
        note: m['note'] as String?,
        frequency: Frequency.values.firstWhere(
            (e) => e.name == m['frequency'],
            orElse: () => Frequency.monthly),
        nextRunDate: DateTime.parse(m['next_run_date'] as String),
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        'account_id': accountId,
        'category_id': categoryId,
        'type': type.name,
        'amount': amount,
        'note': note,
        'frequency': frequency.name,
        'next_run_date': nextRunDate.toIso8601String().split('T').first,
      };

  RecurringRule copyWith({DateTime? nextRunDate}) => RecurringRule(
        id: id,
        accountId: accountId,
        categoryId: categoryId,
        type: type,
        amount: amount,
        note: note,
        frequency: frequency,
        nextRunDate: nextRunDate ?? this.nextRunDate,
      );
}
