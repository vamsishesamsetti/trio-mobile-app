import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase.dart';
import '../profile/profile_repository.dart';
import 'models.dart';
import 'split_engine.dart';
import 'split_repository.dart';

// ---------------------------------------------------------------------------
// Groups
// ---------------------------------------------------------------------------
class GroupsNotifier extends AsyncNotifier<List<Group>> {
  SplitRepository get _repo => ref.read(splitRepositoryProvider);

  @override
  Future<List<Group>> build() => _repo.fetchGroups();

  Future<Group> create(String name, String currency) async {
    final g = await _repo.createGroup(name, currency);
    state = await AsyncValue.guard(_repo.fetchGroups);
    return g;
  }

  Future<void> remove(String id) async {
    await _repo.deleteGroup(id);
    state = await AsyncValue.guard(_repo.fetchGroups);
  }

  Future<void> join(String code) async {
    await _repo.joinGroup(code.trim());
    state = await AsyncValue.guard(_repo.fetchGroups);
  }
}

final groupsProvider =
    AsyncNotifierProvider<GroupsNotifier, List<Group>>(GroupsNotifier.new);

// ---------------------------------------------------------------------------
// Per-group data (family by groupId)
// ---------------------------------------------------------------------------
final groupMembersProvider =
    FutureProvider.family<List<GroupMember>, String>((ref, groupId) {
  return ref.watch(splitRepositoryProvider).fetchMembers(groupId);
});

/// The currency to display a group's amounts in (its own default, else the
/// user's default).
final groupCurrencyProvider = Provider.family<String, String>((ref, groupId) {
  final groups = ref.watch(groupsProvider).value ?? const [];
  for (final g in groups) {
    if (g.id == groupId) return g.defaultCurrency;
  }
  return ref.watch(displayCurrencyProvider);
});

final groupExpensesProvider =
    FutureProvider.family<List<Expense>, String>((ref, groupId) {
  return ref.watch(splitRepositoryProvider).fetchExpenses(groupId);
});

final groupSettlementsProvider =
    FutureProvider.family<List<Settlement>, String>((ref, groupId) {
  return ref.watch(splitRepositoryProvider).fetchSettlements(groupId);
});

final expenseCommentsProvider =
    FutureProvider.family<List<ExpenseComment>, String>((ref, expenseId) {
  return ref.watch(splitRepositoryProvider).fetchComments(expenseId);
});

// ---------------------------------------------------------------------------
// Derived balances
// ---------------------------------------------------------------------------
/// Net balance per member id for a group (positive = owed, negative = owes).
final groupBalancesProvider =
    Provider.family<Map<String, double>, String>((ref, groupId) {
  final members = ref.watch(groupMembersProvider(groupId)).value ?? const [];
  final expenses = (ref.watch(groupExpensesProvider(groupId)).value ?? const [])
      .where((e) => !e.isDeleted)
      .toList();
  final settlements =
      (ref.watch(groupSettlementsProvider(groupId)).value ?? const [])
          .where((s) => !s.isDeleted)
          .toList();
  final ids = members.map((m) => m.userId).whereType<String>();
  return netBalances(
    expenses: expenses,
    settlements: settlements,
    memberIds: ids,
  );
});

/// Suggested settle-up payments for a group.
final groupSimplifiedProvider =
    Provider.family<List<DebtTransfer>, String>((ref, groupId) {
  return simplifyDebts(ref.watch(groupBalancesProvider(groupId)));
});

/// The signed-in user's net in a single group.
final myGroupBalanceProvider =
    Provider.family<double, String>((ref, groupId) {
  final uid = ref.watch(supabaseProvider).auth.currentUser?.id;
  if (uid == null) return 0;
  return ref.watch(groupBalancesProvider(groupId))[uid] ?? 0;
});

/// The signed-in user's net summed across every group (overall headline).
final myOverallBalanceProvider = Provider<double>((ref) {
  final groups = ref.watch(groupsProvider).value ?? const [];
  var total = 0.0;
  for (final g in groups) {
    total += ref.watch(myGroupBalanceProvider(g.id));
  }
  return total;
});

// ---------------------------------------------------------------------------
// Mutations + refresh helper
// ---------------------------------------------------------------------------
class SplitActions {
  SplitActions(this._ref);
  final Ref _ref;
  SplitRepository get _repo => _ref.read(splitRepositoryProvider);

  void refresh(String groupId) {
    _ref.invalidate(groupMembersProvider(groupId));
    _ref.invalidate(groupExpensesProvider(groupId));
    _ref.invalidate(groupSettlementsProvider(groupId));
    _ref.invalidate(expenseCommentsProvider); // all open comment threads
  }

  Future<void> addMember(String groupId, String email) async {
    await _repo.addMemberByEmail(groupId, email);
    _ref.invalidate(groupMembersProvider(groupId));
  }

  Future<void> removeMember(String groupId, String memberRowId) async {
    await _repo.removeMember(memberRowId);
    _ref.invalidate(groupMembersProvider(groupId));
  }

  Future<void> addExpense({
    required String groupId,
    required String paidBy,
    required String description,
    required double amount,
    required String currency,
    required DateTime date,
    required SplitType splitType,
    required String? category,
    required Map<String, double> owedByUser,
    String? receiptUrl,
  }) async {
    await _repo.addExpense(
      groupId: groupId,
      paidBy: paidBy,
      description: description,
      amount: amount,
      currency: currency,
      date: date,
      splitType: splitType,
      category: category,
      owedByUser: owedByUser,
      receiptUrl: receiptUrl,
    );
    _ref.invalidate(groupExpensesProvider(groupId));
  }

  Future<void> updateExpense({
    required String groupId,
    required String expenseId,
    required String paidBy,
    required String description,
    required double amount,
    required String currency,
    required DateTime date,
    required SplitType splitType,
    required String? category,
    required Map<String, double> owedByUser,
    String? receiptUrl,
  }) async {
    await _repo.updateExpense(
      expenseId: expenseId,
      paidBy: paidBy,
      description: description,
      amount: amount,
      currency: currency,
      date: date,
      splitType: splitType,
      category: category,
      owedByUser: owedByUser,
      receiptUrl: receiptUrl,
    );
    _ref.invalidate(groupExpensesProvider(groupId));
  }

  Future<void> deleteExpense(String groupId, String expenseId) async {
    await _repo.deleteExpense(expenseId);
    _ref.invalidate(groupExpensesProvider(groupId));
  }

  Future<String> uploadReceipt(String groupId, List<int> bytes,
          {String ext = 'jpg'}) =>
      _repo.uploadReceipt(groupId, bytes, ext: ext);

  Future<void> settle({
    required String groupId,
    required String fromUser,
    required String toUser,
    required double amount,
  }) async {
    await _repo.addSettlement(
      groupId: groupId,
      fromUser: fromUser,
      toUser: toUser,
      amount: amount,
    );
    _ref.invalidate(groupSettlementsProvider(groupId));
  }

  Future<void> updateSettlement({
    required String groupId,
    required String id,
    required String fromUser,
    required String toUser,
    required double amount,
  }) async {
    await _repo.updateSettlement(
        id: id, fromUser: fromUser, toUser: toUser, amount: amount);
    _ref.invalidate(groupSettlementsProvider(groupId));
  }

  Future<void> deleteSettlement(String groupId, String id) async {
    await _repo.deleteSettlement(id);
    _ref.invalidate(groupSettlementsProvider(groupId));
  }

  Future<void> addComment(String expenseId, String body) async {
    await _repo.addComment(expenseId, body);
    _ref.invalidate(expenseCommentsProvider(expenseId));
  }

  Future<void> deleteComment(String expenseId, String commentId) async {
    await _repo.deleteComment(commentId);
    _ref.invalidate(expenseCommentsProvider(expenseId));
  }
}

final splitActionsProvider =
    Provider<SplitActions>((ref) => SplitActions(ref));
