import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants.dart';
import '../../../core/formatters.dart';
import '../../../core/supabase.dart';
import '../../../core/widgets/async_widgets.dart';
import '../models.dart';
import '../split_providers.dart';
import '../split_repository.dart';
import 'add_expense_page.dart';
import 'expense_detail_page.dart';

class GroupDetailPage extends ConsumerStatefulWidget {
  const GroupDetailPage({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends ConsumerState<GroupDetailPage> {
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    // Live-refresh when any member changes data in this group.
    final repo = ref.read(splitRepositoryProvider);
    _channel = repo.subscribeToGroup(widget.groupId, () {
      if (mounted) ref.read(splitActionsProvider).refresh(widget.groupId);
    });
  }

  @override
  void dispose() {
    if (_channel != null) {
      ref.read(splitRepositoryProvider).removeChannel(_channel!);
    }
    super.dispose();
  }

  String _groupName() {
    final groups = ref.watch(groupsProvider).value ?? const [];
    final g = groups.where((g) => g.id == widget.groupId).firstOrNull;
    return g?.name ?? 'Group';
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(groupMembersProvider(widget.groupId));

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_groupName()),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') _confirmDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Delete group'))),
              ],
            ),
          ],
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Expenses'),
            Tab(text: 'Activity'),
            Tab(text: 'Balances'),
            Tab(text: 'Members'),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final members =
                ref.read(groupMembersProvider(widget.groupId)).value ??
                    const [];
            if (members.where((m) => m.userId != null).isEmpty) {
              showSnack(context, 'Add members first', error: true);
              return;
            }
            await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AddExpensePage(groupId: widget.groupId)));
          },
          icon: const Icon(Icons.add),
          label: const Text('Expense'),
        ),
        body: AsyncView(
          value: membersAsync,
          onRetry: () =>
              ref.invalidate(groupMembersProvider(widget.groupId)),
          data: (members) {
            final labels = {
              for (final m in members)
                if (m.userId != null) m.userId!: m.label,
            };
            return TabBarView(children: [
              _ExpensesTab(groupId: widget.groupId, labels: labels),
              _ActivityTab(
                  groupId: widget.groupId, labels: labels, members: members),
              _BalancesTab(groupId: widget.groupId, labels: labels),
              _MembersTab(groupId: widget.groupId, members: members),
            ]);
          },
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete group?'),
        content: const Text('All its expenses and balances are removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(groupsProvider.notifier).remove(widget.groupId);
    if (mounted) Navigator.of(context).pop();
  }
}

// ---------------------------------------------------------------------------
// Expenses tab
// ---------------------------------------------------------------------------
enum _DateFilter { all, thisMonth, last30, custom }

class _ExpensesTab extends ConsumerStatefulWidget {
  const _ExpensesTab({required this.groupId, required this.labels});
  final String groupId;
  final Map<String, String> labels;

  @override
  ConsumerState<_ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends ConsumerState<_ExpensesTab> {
  String _query = '';
  _DateFilter _filter = _DateFilter.all;
  DateTimeRange? _customRange;

  bool _inRange(DateTime d) {
    final now = DateTime.now();
    switch (_filter) {
      case _DateFilter.all:
        return true;
      case _DateFilter.thisMonth:
        return d.year == now.year && d.month == now.month;
      case _DateFilter.last30:
        return d.isAfter(now.subtract(const Duration(days: 30)));
      case _DateFilter.custom:
        if (_customRange == null) return true;
        final start = DateTime(_customRange!.start.year,
            _customRange!.start.month, _customRange!.start.day);
        final end = _customRange!.end.add(const Duration(days: 1));
        return !d.isBefore(start) && d.isBefore(end);
    }
  }

  bool _matchesQuery(Expense e) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    final payer = (widget.labels[e.paidBy] ?? '').toLowerCase();
    return e.description.toLowerCase().contains(q) ||
        (e.category ?? '').toLowerCase().contains(q) ||
        payer.contains(q);
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
      initialDateRange: _customRange,
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _filter = _DateFilter.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(groupExpensesProvider(widget.groupId));
    final uid = ref.watch(supabaseProvider).auth.currentUser?.id;

    return AsyncView(
      value: async,
      onRetry: () => ref.invalidate(groupExpensesProvider(widget.groupId)),
      data: (all) {
        if (all.isEmpty) {
          return const EmptyView(
              icon: Icons.receipt_long_outlined,
              title: 'No expenses',
              subtitle: 'Tap + to add the first shared expense.');
        }
        final expenses = all
            .where((e) =>
                !e.isDeleted && _matchesQuery(e) && _inRange(e.date))
            .toList();
        final shown = expenses.fold<double>(0, (s, e) => s + e.amount);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search description, category, who paid',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _filterChip('All', _DateFilter.all),
                  _filterChip('This month', _DateFilter.thisMonth),
                  _filterChip('Last 30 days', _DateFilter.last30),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: const Icon(Icons.date_range, size: 18),
                      label: Text(_filter == _DateFilter.custom &&
                              _customRange != null
                          ? '${Fmt.dateShort(_customRange!.start)} – ${Fmt.dateShort(_customRange!.end)}'
                          : 'Custom'),
                      selected: _filter == _DateFilter.custom,
                      onSelected: (_) => _pickCustomRange(),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${expenses.length} expense${expenses.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(
                      'Total ${Fmt.money(shown, ref.watch(groupCurrencyProvider(widget.groupId)))}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Expanded(
              child: expenses.isEmpty
                  ? const EmptyView(
                      icon: Icons.search_off,
                      title: 'No matching expenses',
                      subtitle: 'Try a different search or date range.')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 88),
                      itemCount: expenses.length,
                      itemBuilder: (_, i) {
                        final e = expenses[i];
                        final myShare = e.splits
                                .where((s) => s.userId == uid)
                                .firstOrNull
                                ?.owedAmount ??
                            0;
                        final iPaid = e.paidBy == uid;
                        final lent = iPaid ? e.amount - myShare : -myShare;
                        return Dismissible(
                          key: ValueKey(e.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: Colors.red,
                            child:
                                const Icon(Icons.delete, color: Colors.white),
                          ),
                          onDismissed: (_) => ref
                              .read(splitActionsProvider)
                              .deleteExpense(widget.groupId, e.id),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              child: Icon(
                                  kSplitCategories[e.category] ??
                                      Icons.receipt_long,
                                  size: 20),
                            ),
                            title: Text(e.description),
                            subtitle: Text(
                                '${widget.labels[e.paidBy] ?? 'Someone'} paid ${Fmt.money(e.amount, e.currency)} · ${Fmt.dateShort(e.date)}'),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(lent >= 0 ? 'you lent' : 'you borrowed',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall),
                                Text(
                                  Fmt.money(lent.abs(), e.currency),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: lent >= 0
                                        ? const Color(0xFF2E9E5B)
                                        : const Color(0xFFE0533D),
                                  ),
                                ),
                              ],
                            ),
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => ExpenseDetailPage(
                                          groupId: widget.groupId,
                                          expense: e,
                                          labels: widget.labels,
                                        ))),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _filterChip(String label, _DateFilter value) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _filter == value,
          onSelected: (_) => setState(() => _filter = value),
        ),
      );
}

// ---------------------------------------------------------------------------
// Activity tab — a live, chronological feed everyone in the group sees.
// ---------------------------------------------------------------------------
class _ActivityEntry {
  final DateTime time;
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final bool struck;
  final VoidCallback? onTap;
  final Future<void> Function()? onDelete;
  const _ActivityEntry({
    required this.time,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.struck = false,
    this.onTap,
    this.onDelete,
  });
}

class _ActivityTab extends ConsumerWidget {
  const _ActivityTab(
      {required this.groupId, required this.labels, required this.members});
  final String groupId;
  final Map<String, String> labels;
  final List<GroupMember> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final cur = ref.watch(groupCurrencyProvider(groupId));
    final expenses = ref.watch(groupExpensesProvider(groupId)).value ?? const [];
    final settlements =
        ref.watch(groupSettlementsProvider(groupId)).value ?? const [];

    final items = <_ActivityEntry>[];
    for (final e in expenses) {
      // "Added" event (always — it happened, even if later deleted).
      items.add(_ActivityEntry(
        time: e.createdAt,
        icon: kSplitCategories[e.category] ?? Icons.receipt_long,
        color: scheme.primary,
        title: '${labels[e.paidBy] ?? 'Someone'} added "${e.description}"',
        subtitle: Fmt.money(e.amount, e.currency),
        struck: e.isDeleted,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ExpenseDetailPage(
                groupId: groupId, expense: e, labels: labels))),
        onDelete: e.isDeleted
            ? null
            : () =>
                ref.read(splitActionsProvider).deleteExpense(groupId, e.id),
      ));
      // "Deleted" audit event.
      if (e.isDeleted) {
        items.add(_ActivityEntry(
          time: e.deletedAt!,
          icon: Icons.delete_outline,
          color: scheme.error,
          title:
              '${labels[e.deletedBy] ?? 'Someone'} deleted "${e.description}"',
          subtitle: Fmt.money(e.amount, e.currency),
        ));
      }
    }
    for (final s in settlements) {
      items.add(_ActivityEntry(
        time: s.settledAt,
        icon: Icons.payments,
        color: const Color(0xFF2E9E5B),
        title:
            '${labels[s.fromUser] ?? 'Someone'} paid ${labels[s.toUser] ?? 'someone'}',
        subtitle: Fmt.money(s.amount, cur),
        struck: s.isDeleted,
        onTap: s.isDeleted
            ? null
            : () => showSettleSheet(context,
                groupId: groupId,
                labels: labels,
                from: s.fromUser,
                to: s.toUser,
                amount: s.amount,
                settlementId: s.id),
        onDelete: s.isDeleted
            ? null
            : () => ref
                .read(splitActionsProvider)
                .deleteSettlement(groupId, s.id),
      ));
      if (s.isDeleted) {
        items.add(_ActivityEntry(
          time: s.deletedAt!,
          icon: Icons.delete_outline,
          color: scheme.error,
          title:
              '${labels[s.deletedBy] ?? 'Someone'} deleted a payment (${labels[s.fromUser] ?? '?'} → ${labels[s.toUser] ?? '?'})',
          subtitle: Fmt.money(s.amount, cur),
        ));
      }
    }
    for (final m in members) {
      if (m.createdAt != null) {
        items.add(_ActivityEntry(
          time: m.createdAt!,
          icon: Icons.person_add_alt_1,
          color: scheme.tertiary,
          title: '${m.label} joined the group',
        ));
      }
    }
    items.sort((a, b) => b.time.compareTo(a.time));

    if (items.isEmpty) {
      return const EmptyView(
          icon: Icons.history,
          title: 'No activity yet',
          subtitle: 'Expenses, payments and new members will show up here.');
    }

    return RefreshIndicator(
      onRefresh: () async =>
          ref.read(splitActionsProvider).refresh(groupId),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final it = items[i];
          final tile = ListTile(
            leading: CircleAvatar(
              backgroundColor: it.color.withValues(alpha: 0.16),
              child: Icon(it.icon, color: it.color, size: 20),
            ),
            title: Text(it.title,
                style: it.struck
                    ? const TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: Colors.grey)
                    : null),
            subtitle: Text(Fmt.dateTime(it.time)),
            trailing: it.subtitle == null
                ? null
                : Text(it.subtitle!,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        decoration: it.struck
                            ? TextDecoration.lineThrough
                            : null)),
            onTap: it.onTap,
          );
          if (it.onDelete == null) return tile;
          return Dismissible(
            key: ValueKey('act_${it.time.microsecondsSinceEpoch}_$i'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: Colors.red,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) async {
              try {
                await it.onDelete!();
              } catch (e) {
                if (context.mounted) {
                  showSnack(context, 'Delete failed — did you run v2_features.sql? ($e)',
                      error: true);
                }
              }
              return false; // list refreshes from provider, no manual removal
            },
            child: tile,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Balances tab
// ---------------------------------------------------------------------------
class _BalancesTab extends ConsumerWidget {
  const _BalancesTab({required this.groupId, required this.labels});
  final String groupId;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cur = ref.watch(groupCurrencyProvider(groupId));
    final balances = ref.watch(groupBalancesProvider(groupId));
    final suggestions = ref.watch(groupSimplifiedProvider(groupId));
    final entries = balances.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Per-member spend stats (non-deleted expenses only).
    final expenses = (ref.watch(groupExpensesProvider(groupId)).value ?? const [])
        .where((e) => !e.isDeleted)
        .toList();
    final totalSpent = expenses.fold<double>(0, (s, e) => s + e.amount);
    final paidByMember = <String, double>{};
    final shareByMember = <String, double>{};
    for (final e in expenses) {
      paidByMember[e.paidBy] = (paidByMember[e.paidBy] ?? 0) + e.amount;
      for (final sp in e.splits) {
        shareByMember[sp.userId] =
            (shareByMember[sp.userId] ?? 0) + sp.owedAmount;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Group total spent',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(Fmt.money(totalSpent, cur),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                for (final id in labels.keys)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(labels[id] ?? 'Member'),
                        Text(
                            'paid ${Fmt.money(paidByMember[id] ?? 0, cur)} · share ${Fmt.money(shareByMember[id] ?? 0, cur)}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Balances', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final e in entries)
          ListTile(
            leading: CircleAvatar(
                child: Text((labels[e.key] ?? '?')[0].toUpperCase())),
            title: Text(labels[e.key] ?? 'Member'),
            trailing: Text(
              e.value.abs() < 0.01
                  ? 'settled'
                  : (e.value > 0
                      ? 'gets ${Fmt.money(e.value, cur)}'
                      : 'owes ${Fmt.money(-e.value, cur)}'),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: e.value.abs() < 0.01
                    ? null
                    : (e.value > 0
                        ? const Color(0xFF2E9E5B)
                        : const Color(0xFFE0533D)),
              ),
            ),
          ),
        const Divider(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Settle up', style: Theme.of(context).textTheme.titleMedium),
            TextButton.icon(
              onPressed: () =>
                  showSettleSheet(context, groupId: groupId, labels: labels),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Record payment'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (suggestions.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Everyone is settled up 🎉'),
          )
        else ...[
          Text('Suggested payments — tap to record (you can change the amount):',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final t in suggestions)
            Card(
              child: ListTile(
                leading: const Icon(Icons.arrow_forward),
                title: Text(
                    '${labels[t.from] ?? 'Someone'} → ${labels[t.to] ?? 'Someone'}'),
                trailing: Text(Fmt.money(t.amount, cur),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                onTap: () => showSettleSheet(context,
                    groupId: groupId,
                    labels: labels,
                    from: t.from,
                    to: t.to,
                    amount: t.amount),
              ),
            ),
        ],
      ],
    );
  }

}

/// Opens the settle sheet to record a new payment, or (with [settlementId]) to
/// edit an existing one. Usable from any tab.
void showSettleSheet(
  BuildContext context, {
  required String groupId,
  required Map<String, String> labels,
  String? from,
  String? to,
  double? amount,
  String? settlementId,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SettleSheet(
      groupId: groupId,
      labels: labels,
      initialFrom: from,
      initialTo: to,
      initialAmount: amount,
      settlementId: settlementId,
    ),
  );
}

/// Bottom sheet to record a payment of any amount between two members.
/// Pre-filled when launched from a suggested settlement, but fully editable.
class _SettleSheet extends ConsumerStatefulWidget {
  const _SettleSheet({
    required this.groupId,
    required this.labels,
    this.initialFrom,
    this.initialTo,
    this.initialAmount,
    this.settlementId,
  });

  final String groupId;
  final Map<String, String> labels;
  final String? initialFrom;
  final String? initialTo;
  final double? initialAmount;
  final String? settlementId; // non-null => editing an existing payment

  @override
  ConsumerState<_SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends ConsumerState<_SettleSheet> {
  String? _from;
  String? _to;
  late TextEditingController _amount;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _from = widget.initialFrom;
    _to = widget.initialTo;
    _amount = TextEditingController(
        text: widget.initialAmount == null
            ? ''
            : widget.initialAmount!.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (_from == null || _to == null) {
      showSnack(context, 'Pick who pays and who receives', error: true);
      return;
    }
    if (_from == _to) {
      showSnack(context, 'Pick two different people', error: true);
      return;
    }
    if (amount == null || amount <= 0) {
      showSnack(context, 'Enter a valid amount', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final actions = ref.read(splitActionsProvider);
      if (widget.settlementId != null) {
        await actions.updateSettlement(
          groupId: widget.groupId,
          id: widget.settlementId!,
          fromUser: _from!,
          toUser: _to!,
          amount: amount,
        );
      } else {
        await actions.settle(
          groupId: widget.groupId,
          fromUser: _from!,
          toUser: _to!,
          amount: amount,
        );
      }
      if (mounted) {
        Navigator.pop(context);
        showSnack(context,
            widget.settlementId != null ? 'Payment updated' : 'Payment recorded');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.labels.entries.toList();
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.settlementId != null ? 'Edit payment' : 'Record a payment',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _from,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Who paid', prefixIcon: Icon(Icons.person)),
            items: [
              for (final e in entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _from = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _to,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Paid to', prefixIcon: Icon(Icons.person_outline)),
            items: [
              for (final e in entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _to = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            decoration: const InputDecoration(
                labelText: 'Amount', prefixIcon: Icon(Icons.attach_money)),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4))
                : const Text('Record payment'),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Members tab
// ---------------------------------------------------------------------------
class _MembersTab extends ConsumerWidget {
  const _MembersTab({required this.groupId, required this.members});
  final String groupId;
  final List<GroupMember> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
      children: [
        for (final m in members)
          ListTile(
            leading: CircleAvatar(child: Text(m.label[0].toUpperCase())),
            title: Text(m.label),
            subtitle: Text(m.role),
            trailing: m.role == 'owner'
                ? const Chip(label: Text('owner'))
                : IconButton(
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: () => ref
                        .read(splitActionsProvider)
                        .removeMember(groupId, m.id),
                  ),
          ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: FilledButton.icon(
            onPressed: () => _addMember(context, ref),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add member by email'),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: OutlinedButton.icon(
            onPressed: () => _shareInvite(context, ref),
            icon: const Icon(Icons.ios_share),
            label: const Text('Share invite link'),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text('Invite code: $groupId',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }

  Future<void> _shareInvite(BuildContext context, WidgetRef ref) async {
    final groups = ref.read(groupsProvider).value ?? const [];
    final name =
        groups.where((g) => g.id == groupId).firstOrNull?.name ?? 'my group';
    final link = 'trio://join/$groupId';
    final message = 'Join "$name" on Trio!\n\n'
        'Open the Trio app → Split tab → menu → "Join group", '
        'and paste this invite code:\n$groupId\n\n'
        '(Link: $link)';
    await SharePlus.instance
        .share(ShareParams(text: message, subject: 'Trio group invite'));
  }

  Future<void> _addMember(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Add member'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
              labelText: 'Email', hintText: 'They must have a Trio account'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogCtx, controller.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;
    try {
      await ref.read(splitActionsProvider).addMember(groupId, email);
      if (context.mounted) showSnack(context, 'Member added');
    } catch (e) {
      if (context.mounted) {
        showSnack(context, '$e'.replaceFirst('Exception: ', ''), error: true);
      }
    }
  }
}
