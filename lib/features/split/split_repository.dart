import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';
import 'models.dart';
import 'split_engine.dart';

class SplitRepository {
  SplitRepository(this._ref, this._db);
  final Ref _ref;
  final SupabaseClient _db;

  String get _uid => requireUserId(_ref);

  // ---- Groups ----
  Future<List<Group>> fetchGroups() async {
    final rows = await _db.from('groups').select().order('created_at');
    return rows.map((e) => Group.fromMap(e)).toList();
  }

  Future<Group> createGroup(String name, String currency) async {
    final row = await _db
        .from('groups')
        .insert({
          'name': name,
          'created_by': _uid,
          'default_currency': currency,
        })
        .select()
        .single();
    final group = Group.fromMap(row);
    // Creator joins as owner.
    await _db.from('group_members').insert({
      'group_id': group.id,
      'user_id': _uid,
      'role': 'owner',
    });
    return group;
  }

  Future<void> deleteGroup(String id) =>
      _db.from('groups').delete().eq('id', id);

  // ---- Members ----
  Future<List<GroupMember>> fetchMembers(String groupId) async {
    final rows =
        await _db.from('group_members').select().eq('group_id', groupId);
    final members = rows.map((e) => GroupMember.fromMap(e)).toList();

    // Resolve display names via a second query. We don't embed profiles
    // because group_members.user_id FKs to auth.users, not public.profiles,
    // so PostgREST can't auto-join them.
    final userIds =
        members.map((m) => m.userId).whereType<String>().toSet().toList();
    if (userIds.isEmpty) return members;

    final profiles = await _db
        .from('profiles')
        .select('id, display_name')
        .inFilter('id', userIds);
    final nameById = {
      for (final p in profiles) p['id'] as String: p['display_name'] as String?,
    };
    return [
      for (final m in members)
        m.userId != null ? m.withDisplayName(nameById[m.userId]) : m,
    ];
  }

  /// Adds an existing Trio user (looked up by email) to a group. Throws a
  /// readable error if no account with that email exists.
  Future<void> addMemberByEmail(String groupId, String email) async {
    final found = await _db
        .from('profiles')
        .select('id')
        .eq('email', email.trim().toLowerCase())
        .maybeSingle();
    if (found == null) {
      throw Exception('No Trio user with that email. Ask them to sign up first.');
    }
    await _db.from('group_members').insert({
      'group_id': groupId,
      'user_id': found['id'],
      'role': 'member',
    });
  }

  Future<void> removeMember(String memberRowId) =>
      _db.from('group_members').delete().eq('id', memberRowId);

  /// Join a group via an invite code (the group's id). RLS allows a user to
  /// add a membership row for themselves.
  Future<void> joinGroup(String groupId) async {
    await _db.from('group_members').insert({
      'group_id': groupId,
      'user_id': _uid,
      'role': 'member',
    });
  }

  // ---- Expenses ----
  Future<List<Expense>> fetchExpenses(String groupId) async {
    final rows = await _db
        .from('expenses')
        .select('*, expense_splits(*)')
        .eq('group_id', groupId)
        .order('expense_date', ascending: false)
        .order('created_at', ascending: false);
    return rows.map((e) => Expense.fromMap(e)).toList();
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
    final row = await _db
        .from('expenses')
        .insert({
          'group_id': groupId,
          'paid_by': paidBy,
          'description': description,
          'amount': amount,
          'currency': currency,
          'expense_date': date.toIso8601String().split('T').first,
          'split_type': splitType.name,
          'category': category,
          'receipt_url': receiptUrl,
          'created_by': _uid,
        })
        .select()
        .single();
    await _writeSplits(row['id'] as String, owedByUser);
  }

  /// Updates an existing expense and replaces its splits.
  Future<void> updateExpense({
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
    await _db.from('expenses').update({
      'paid_by': paidBy,
      'description': description,
      'amount': amount,
      'currency': currency,
      'expense_date': date.toIso8601String().split('T').first,
      'split_type': splitType.name,
      'category': category,
      'receipt_url': ?receiptUrl,
    }).eq('id', expenseId);
    await _db.from('expense_splits').delete().eq('expense_id', expenseId);
    await _writeSplits(expenseId, owedByUser);
  }

  Future<void> _writeSplits(
      String expenseId, Map<String, double> owedByUser) async {
    final splits = [
      for (final e in owedByUser.entries)
        {'expense_id': expenseId, 'user_id': e.key, 'owed_amount': e.value}
    ];
    if (splits.isNotEmpty) {
      await _db.from('expense_splits').insert(splits);
    }
  }

  /// Soft-delete: keeps the row but records who removed it and when, so the
  /// activity feed can show "X deleted ...".
  Future<void> deleteExpense(String id) => _db.from('expenses').update({
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'deleted_by': _uid,
      }).eq('id', id);

  /// Uploads a receipt image and returns its public URL.
  Future<String> uploadReceipt(String groupId, List<int> bytes,
      {String ext = 'jpg'}) async {
    final path =
        '$_uid/${groupId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _db.storage.from('receipts').uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(upsert: true),
        );
    return _db.storage.from('receipts').getPublicUrl(path);
  }

  // ---- Settlements ----
  Future<List<Settlement>> fetchSettlements(String groupId) async {
    final rows = await _db
        .from('settlements')
        .select()
        .eq('group_id', groupId)
        .order('settled_at', ascending: false);
    return rows.map((e) => Settlement.fromMap(e)).toList();
  }

  Future<void> addSettlement({
    required String groupId,
    required String fromUser,
    required String toUser,
    required double amount,
  }) {
    return _db.from('settlements').insert({
      'group_id': groupId,
      'from_user': fromUser,
      'to_user': toUser,
      'amount': amount,
    });
  }

  Future<void> updateSettlement({
    required String id,
    required String fromUser,
    required String toUser,
    required double amount,
  }) {
    return _db.from('settlements').update({
      'from_user': fromUser,
      'to_user': toUser,
      'amount': amount,
    }).eq('id', id);
  }

  Future<void> deleteSettlement(String id) =>
      _db.from('settlements').update({
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'deleted_by': _uid,
      }).eq('id', id);

  // ---- Comments ----
  Future<List<ExpenseComment>> fetchComments(String expenseId) async {
    final rows = await _db
        .from('expense_comments')
        .select()
        .eq('expense_id', expenseId)
        .order('created_at');
    final comments = rows.map((e) => ExpenseComment.fromMap(e)).toList();

    final userIds =
        comments.map((c) => c.userId).toSet().toList();
    if (userIds.isEmpty) return comments;
    final profiles = await _db
        .from('profiles')
        .select('id, display_name')
        .inFilter('id', userIds);
    final nameById = {
      for (final p in profiles) p['id'] as String: p['display_name'] as String?,
    };
    return [for (final c in comments) c.withDisplayName(nameById[c.userId])];
  }

  Future<void> addComment(String expenseId, String body) {
    return _db.from('expense_comments').insert({
      'expense_id': expenseId,
      'user_id': _uid,
      'body': body,
    });
  }

  Future<void> deleteComment(String id) =>
      _db.from('expense_comments').delete().eq('id', id);

  /// Live channel for a group's expenses + settlements. Calls [onChange] on any
  /// insert/update/delete so the UI can refresh. Remember to removeChannel.
  RealtimeChannel subscribeToGroup(String groupId, void Function() onChange) {
    final channel = _db.channel('group:$groupId');
    for (final table in [
      'expenses',
      'settlements',
      'expense_splits',
      'expense_comments',
      'group_members',
    ]) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => onChange(),
      );
    }
    channel.subscribe();
    return channel;
  }

  void removeChannel(RealtimeChannel channel) => _db.removeChannel(channel);
}

final splitRepositoryProvider = Provider<SplitRepository>((ref) {
  return SplitRepository(ref, ref.watch(supabaseProvider));
});

/// Convenience export so UI can build settle-up suggestions.
typedef Suggestion = DebtTransfer;
