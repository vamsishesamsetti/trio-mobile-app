import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';
import 'models.dart';

/// All Money Tracker reads/writes. RLS guarantees rows are scoped to the
/// signed-in user, so queries don't need explicit user_id filters (but we add
/// user_id on insert because columns are NOT NULL).
class MoneyRepository {
  MoneyRepository(this._ref, this._db);
  final Ref _ref;
  final SupabaseClient _db;

  String get _uid => requireUserId(_ref);

  // ---- Accounts ----
  Future<List<Account>> fetchAccounts() async {
    final rows = await _db.from('accounts').select().order('created_at');
    return rows.map((e) => Account.fromMap(e)).toList();
  }

  Future<void> addAccount(Account a) =>
      _db.from('accounts').insert(a.toInsert(_uid));

  Future<void> updateAccount(Account a) => _db
      .from('accounts')
      .update(a.toInsert(_uid)..remove('user_id'))
      .eq('id', a.id);

  Future<void> deleteAccount(String id) =>
      _db.from('accounts').delete().eq('id', id);

  // ---- Categories ----
  Future<List<Category>> fetchCategories() async {
    final rows = await _db.from('categories').select().order('name');
    return rows.map((e) => Category.fromMap(e)).toList();
  }

  Future<void> addCategory(Category c) =>
      _db.from('categories').insert(c.toInsert(_uid));

  Future<void> updateCategory(Category c) => _db
      .from('categories')
      .update(c.toInsert(_uid)..remove('user_id'))
      .eq('id', c.id);

  Future<void> deleteCategory(String id) =>
      _db.from('categories').delete().eq('id', id);

  // ---- Transactions ----
  Future<List<MoneyTransaction>> fetchTransactions() async {
    final rows = await _db
        .from('transactions')
        .select()
        .order('txn_date', ascending: false)
        .order('created_at', ascending: false);
    return rows.map((e) => MoneyTransaction.fromMap(e)).toList();
  }

  Future<void> addTransaction(MoneyTransaction t) =>
      _db.from('transactions').insert(t.toInsert(_uid));

  Future<void> updateTransaction(MoneyTransaction t) => _db
      .from('transactions')
      .update(t.toInsert(_uid)..remove('user_id'))
      .eq('id', t.id);

  Future<void> deleteTransaction(String id) =>
      _db.from('transactions').delete().eq('id', id);

  // ---- Budgets ----
  Future<List<Budget>> fetchBudgets() async {
    final rows = await _db.from('budgets').select().order('created_at');
    return rows.map((e) => Budget.fromMap(e)).toList();
  }

  Future<void> addBudget(Budget b) =>
      _db.from('budgets').insert(b.toInsert(_uid));

  Future<void> deleteBudget(String id) =>
      _db.from('budgets').delete().eq('id', id);

  // ---- Recurring rules ----
  Future<List<RecurringRule>> fetchRecurring() async {
    final rows =
        await _db.from('recurring_rules').select().order('next_run_date');
    return rows.map((e) => RecurringRule.fromMap(e)).toList();
  }

  Future<void> addRecurring(RecurringRule r) =>
      _db.from('recurring_rules').insert(r.toInsert(_uid));

  Future<void> deleteRecurring(String id) =>
      _db.from('recurring_rules').delete().eq('id', id);

  Future<void> updateRecurringNextRun(String id, DateTime next) => _db
      .from('recurring_rules')
      .update({'next_run_date': next.toIso8601String().split('T').first})
      .eq('id', id);
}

final moneyRepositoryProvider = Provider<MoneyRepository>((ref) {
  return MoneyRepository(ref, ref.watch(supabaseProvider));
});
