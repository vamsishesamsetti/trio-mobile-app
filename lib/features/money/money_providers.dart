import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../profile/profile_repository.dart';
import 'models.dart';
import 'money_repository.dart';

// ---------------------------------------------------------------------------
// Entity notifiers (load + mutate, then refresh from the server).
// ---------------------------------------------------------------------------
class AccountsNotifier extends AsyncNotifier<List<Account>> {
  MoneyRepository get _repo => ref.read(moneyRepositoryProvider);

  @override
  Future<List<Account>> build() => _repo.fetchAccounts();

  Future<void> _reload() async {
    state = await AsyncValue.guard(_repo.fetchAccounts);
  }

  Future<void> add(Account a) async {
    await _repo.addAccount(a);
    await _reload();
  }

  Future<void> edit(Account a) async {
    await _repo.updateAccount(a);
    await _reload();
  }

  Future<void> remove(String id) async {
    await _repo.deleteAccount(id);
    await _reload();
    ref.invalidate(transactionsProvider);
  }
}

final accountsProvider =
    AsyncNotifierProvider<AccountsNotifier, List<Account>>(
        AccountsNotifier.new);

class CategoriesNotifier extends AsyncNotifier<List<Category>> {
  MoneyRepository get _repo => ref.read(moneyRepositoryProvider);

  @override
  Future<List<Category>> build() => _repo.fetchCategories();

  Future<void> _reload() async {
    state = await AsyncValue.guard(_repo.fetchCategories);
  }

  Future<void> add(Category c) async {
    await _repo.addCategory(c);
    await _reload();
  }

  Future<void> edit(Category c) async {
    await _repo.updateCategory(c);
    await _reload();
  }

  Future<void> remove(String id) async {
    await _repo.deleteCategory(id);
    await _reload();
  }
}

final categoriesProvider =
    AsyncNotifierProvider<CategoriesNotifier, List<Category>>(
        CategoriesNotifier.new);

class TransactionsNotifier extends AsyncNotifier<List<MoneyTransaction>> {
  MoneyRepository get _repo => ref.read(moneyRepositoryProvider);

  @override
  Future<List<MoneyTransaction>> build() => _repo.fetchTransactions();

  Future<void> _reload() async {
    state = await AsyncValue.guard(_repo.fetchTransactions);
  }

  Future<void> add(MoneyTransaction t) async {
    await _repo.addTransaction(t);
    await _reload();
    ref.invalidate(accountsProvider);
  }

  Future<void> edit(MoneyTransaction t) async {
    await _repo.updateTransaction(t);
    await _reload();
    ref.invalidate(accountsProvider);
  }

  Future<void> remove(String id) async {
    await _repo.deleteTransaction(id);
    await _reload();
    ref.invalidate(accountsProvider);
  }
}

final transactionsProvider =
    AsyncNotifierProvider<TransactionsNotifier, List<MoneyTransaction>>(
        TransactionsNotifier.new);

class BudgetsNotifier extends AsyncNotifier<List<Budget>> {
  MoneyRepository get _repo => ref.read(moneyRepositoryProvider);

  @override
  Future<List<Budget>> build() => _repo.fetchBudgets();

  Future<void> _reload() async {
    state = await AsyncValue.guard(_repo.fetchBudgets);
  }

  Future<void> add(Budget b) async {
    await _repo.addBudget(b);
    await _reload();
  }

  Future<void> remove(String id) async {
    await _repo.deleteBudget(id);
    await _reload();
  }
}

final budgetsProvider =
    AsyncNotifierProvider<BudgetsNotifier, List<Budget>>(BudgetsNotifier.new);

class RecurringNotifier extends AsyncNotifier<List<RecurringRule>> {
  MoneyRepository get _repo => ref.read(moneyRepositoryProvider);

  @override
  Future<List<RecurringRule>> build() => _repo.fetchRecurring();

  Future<void> _reload() async {
    state = await AsyncValue.guard(_repo.fetchRecurring);
  }

  Future<void> add(RecurringRule r) async {
    await _repo.addRecurring(r);
    await _reload();
  }

  Future<void> remove(String id) async {
    await _repo.deleteRecurring(id);
    await _reload();
  }
}

final recurringProvider =
    AsyncNotifierProvider<RecurringNotifier, List<RecurringRule>>(
        RecurringNotifier.new);

// ---------------------------------------------------------------------------
// Lookups
// ---------------------------------------------------------------------------
final categoryByIdProvider = Provider<Map<String, Category>>((ref) {
  final list = ref.watch(categoriesProvider).value ?? const [];
  return {for (final c in list) c.id: c};
});

final accountByIdProvider = Provider<Map<String, Account>>((ref) {
  final list = ref.watch(accountsProvider).value ?? const [];
  return {for (final a in list) a.id: a};
});

/// Base currency for display — the user's saved default currency.
final baseCurrencyProvider = Provider<String>((ref) {
  return ref.watch(displayCurrencyProvider);
});

// ---------------------------------------------------------------------------
// Balances
// ---------------------------------------------------------------------------
double balanceForAccount(Account a, List<MoneyTransaction> txns) {
  var bal = a.openingBalance;
  for (final t in txns) {
    switch (t.type) {
      case TxnType.income:
        if (t.accountId == a.id) bal += t.amount;
      case TxnType.expense:
        if (t.accountId == a.id) bal -= t.amount;
      case TxnType.transfer:
        if (t.accountId == a.id) bal -= t.amount;
        if (t.transferAccountId == a.id) bal += t.amount;
    }
  }
  return bal;
}

final accountBalancesProvider = Provider<Map<String, double>>((ref) {
  final accts = ref.watch(accountsProvider).value ?? const [];
  final txns = ref.watch(transactionsProvider).value ?? const [];
  return {for (final a in accts) a.id: balanceForAccount(a, txns)};
});

final totalBalanceProvider = Provider<double>((ref) {
  final balances = ref.watch(accountBalancesProvider);
  return balances.values.fold<double>(0, (s, v) => s + v);
});

// ---------------------------------------------------------------------------
// Selected month + monthly aggregates
// ---------------------------------------------------------------------------
class MonthController extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  void next() => state = DateTime(state.year, state.month + 1);
  void prev() => state = DateTime(state.year, state.month - 1);
  void reset() {
    final now = DateTime.now();
    state = DateTime(now.year, now.month);
  }
}

final selectedMonthProvider =
    NotifierProvider<MonthController, DateTime>(MonthController.new);

bool _sameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

final monthTransactionsProvider = Provider<List<MoneyTransaction>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  final txns = ref.watch(transactionsProvider).value ?? const [];
  return txns.where((t) => _sameMonth(t.date, month)).toList();
});

class MonthSummary {
  final double income;
  final double expense;
  const MonthSummary(this.income, this.expense);
  double get net => income - expense;
}

final monthSummaryProvider = Provider<MonthSummary>((ref) {
  final txns = ref.watch(monthTransactionsProvider);
  var income = 0.0, expense = 0.0;
  for (final t in txns) {
    if (t.type == TxnType.income) income += t.amount;
    if (t.type == TxnType.expense) expense += t.amount;
  }
  return MonthSummary(income, expense);
});

/// Spend grouped by category id for the selected month (expenses only).
final monthSpendByCategoryProvider = Provider<Map<String, double>>((ref) {
  final txns = ref.watch(monthTransactionsProvider);
  final byCat = <String, double>{};
  for (final t in txns.where((t) => t.type == TxnType.expense)) {
    final key = t.categoryId ?? '_uncategorized';
    byCat[key] = (byCat[key] ?? 0) + t.amount;
  }
  return byCat;
});

/// 6-month income/expense trend for the line/bar chart, oldest first.
class MonthBucket {
  final DateTime month;
  final double income;
  final double expense;
  const MonthBucket(this.month, this.income, this.expense);
}

final trendProvider = Provider<List<MonthBucket>>((ref) {
  final txns = ref.watch(transactionsProvider).value ?? const [];
  final now = DateTime.now();
  final buckets = <MonthBucket>[];
  for (var i = 5; i >= 0; i--) {
    final m = DateTime(now.year, now.month - i);
    final monthTxns = txns.where((t) => _sameMonth(t.date, m));
    var inc = 0.0, exp = 0.0;
    for (final t in monthTxns) {
      if (t.type == TxnType.income) inc += t.amount;
      if (t.type == TxnType.expense) exp += t.amount;
    }
    buckets.add(MonthBucket(m, inc, exp));
  }
  return buckets;
});

// ---------------------------------------------------------------------------
// Budget progress (how much of each budget is spent in its current period)
// ---------------------------------------------------------------------------
class BudgetProgress {
  final Budget budget;
  final Category? category;
  final double spent;
  const BudgetProgress(this.budget, this.category, this.spent);
  double get ratio => budget.amount == 0 ? 0 : spent / budget.amount;
  double get remaining => budget.amount - spent;
  bool get over => spent > budget.amount;
}

({DateTime start, DateTime end}) _periodWindow(BudgetPeriod p, DateTime now) {
  switch (p) {
    case BudgetPeriod.weekly:
      final start = now.subtract(Duration(days: now.weekday - 1));
      final s = DateTime(start.year, start.month, start.day);
      return (start: s, end: s.add(const Duration(days: 7)));
    case BudgetPeriod.monthly:
      final s = DateTime(now.year, now.month);
      return (start: s, end: DateTime(now.year, now.month + 1));
    case BudgetPeriod.yearly:
      final s = DateTime(now.year);
      return (start: s, end: DateTime(now.year + 1));
  }
}

final budgetProgressProvider = Provider<List<BudgetProgress>>((ref) {
  final budgets = ref.watch(budgetsProvider).value ?? const [];
  final txns = ref.watch(transactionsProvider).value ?? const [];
  final cats = ref.watch(categoryByIdProvider);
  final now = DateTime.now();

  return budgets.map((b) {
    final w = _periodWindow(b.period, now);
    final spent = txns
        .where((t) =>
            t.type == TxnType.expense &&
            t.categoryId == b.categoryId &&
            !t.date.isBefore(w.start) &&
            t.date.isBefore(w.end))
        .fold<double>(0, (s, t) => s + t.amount);
    return BudgetProgress(b, cats[b.categoryId], spent);
  }).toList();
});

// ---------------------------------------------------------------------------
// Recurring materialization — turn due rules into transactions on app open.
// ---------------------------------------------------------------------------
DateTime advanceDate(DateTime d, Frequency f) {
  switch (f) {
    case Frequency.daily:
      return d.add(const Duration(days: 1));
    case Frequency.weekly:
      return d.add(const Duration(days: 7));
    case Frequency.monthly:
      return DateTime(d.year, d.month + 1, d.day);
    case Frequency.yearly:
      return DateTime(d.year + 1, d.month, d.day);
  }
}

final recurringMaterializerProvider = FutureProvider<int>((ref) async {
  final repo = ref.read(moneyRepositoryProvider);
  final currency = ref.read(displayCurrencyProvider);
  final rules = await repo.fetchRecurring();
  final today = DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);
  var created = 0;

  for (final rule in rules) {
    var next = rule.nextRunDate;
    // Catch up any missed occurrences, capped to avoid runaway loops.
    var guard = 0;
    while (!next.isAfter(todayDate) && guard < 366) {
      await repo.addTransaction(MoneyTransaction(
        id: '',
        accountId: rule.accountId,
        categoryId: rule.categoryId,
        type: rule.type,
        amount: rule.amount,
        currency: currency,
        date: next,
        note: rule.note ?? 'Recurring',
      ));
      created++;
      next = advanceDate(next, rule.frequency);
      guard++;
    }
    if (next != rule.nextRunDate) {
      await repo.updateRecurringNextRun(rule.id, next);
    }
  }

  if (created > 0) {
    ref.invalidate(transactionsProvider);
    ref.invalidate(accountsProvider);
    ref.invalidate(recurringProvider);
  }
  return created;
});
