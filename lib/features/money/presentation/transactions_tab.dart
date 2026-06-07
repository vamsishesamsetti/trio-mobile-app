import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/widgets/async_widgets.dart';
import '../models.dart';
import '../money_providers.dart';
import '../transaction_editor.dart';
import '../widgets.dart';

class TransactionsTab extends ConsumerStatefulWidget {
  const TransactionsTab({super.key});

  @override
  ConsumerState<TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends ConsumerState<TransactionsTab> {
  String _query = '';
  TxnType? _filter;

  @override
  Widget build(BuildContext context) {
    final base = ref.watch(baseCurrencyProvider);
    final cats = ref.watch(categoryByIdProvider);
    final accts = ref.watch(accountByIdProvider);
    final monthTxns = ref.watch(monthTransactionsProvider);

    var list = monthTxns;
    if (_filter != null) {
      list = list.where((t) => t.type == _filter).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((t) {
        final catName = cats[t.categoryId]?.name.toLowerCase() ?? '';
        final note = t.note?.toLowerCase() ?? '';
        return catName.contains(q) || note.contains(q);
      }).toList();
    }

    // Group by date (yyyy-mm-dd).
    final grouped = <String, List<MoneyTransaction>>{};
    for (final t in list) {
      final key = t.date.toIso8601String().split('T').first;
      grouped.putIfAbsent(key, () => []).add(t);
    }
    final dayKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search notes & categories',
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
              _chip('All', _filter == null, () => setState(() => _filter = null)),
              _chip('Expense', _filter == TxnType.expense,
                  () => setState(() => _filter = TxnType.expense)),
              _chip('Income', _filter == TxnType.income,
                  () => setState(() => _filter = TxnType.income)),
              _chip('Transfer', _filter == TxnType.transfer,
                  () => setState(() => _filter = TxnType.transfer)),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const EmptyView(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions',
                  subtitle: 'Tap + to add one for this month.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                  itemCount: dayKeys.length,
                  itemBuilder: (_, i) {
                    final key = dayKeys[i];
                    final items = grouped[key]!;
                    final dayTotal = items.fold<double>(0, (s, t) {
                      if (t.type == TxnType.income) return s + t.amount;
                      if (t.type == TxnType.expense) return s - t.amount;
                      return s;
                    });
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(Fmt.dateFull(DateTime.parse(key)),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge),
                              Text(Fmt.money(dayTotal, base, sign: true),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium),
                            ],
                          ),
                        ),
                        for (final t in items)
                          _TxnTile(
                              txn: t,
                              base: base,
                              catName: cats[t.categoryId]?.name,
                              catIcon: cats[t.categoryId]?.icon,
                              catColor: cats[t.categoryId]?.color,
                              fromAccount: accts[t.accountId]?.name,
                              toAccount:
                                  accts[t.transferAccountId]?.name,
                              onDelete: () => ref
                                  .read(transactionsProvider.notifier)
                                  .remove(t.id)),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
        ),
      );
}

class _TxnTile extends StatelessWidget {
  const _TxnTile({
    required this.txn,
    required this.base,
    required this.catName,
    required this.catIcon,
    required this.catColor,
    required this.fromAccount,
    required this.toAccount,
    required this.onDelete,
  });
  final MoneyTransaction txn;
  final String base;
  final String? catName;
  final String? catIcon;
  final String? catColor;
  final String? fromAccount;
  final String? toAccount;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isTransfer = txn.type == TxnType.transfer;
    final title = isTransfer
        ? '${fromAccount ?? '?'} → ${toAccount ?? '?'}'
        : (catName ?? txn.note ?? 'Transaction');
    final subtitleParts = <String>[
      if (!isTransfer && fromAccount != null) fromAccount!,
      if (txn.note != null && txn.note!.isNotEmpty) txn.note!,
    ];
    return Dismissible(
      key: ValueKey(txn.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
            color: Colors.red, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        leading: isTransfer
            ? const CircleAvatar(child: Icon(Icons.swap_horiz))
            : IconBadge(iconName: catIcon, color: catColor, size: 42),
        title: Text(title),
        subtitle:
            subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
        trailing: AmountText(
          Fmt.money(txn.amount, base),
          positive: txn.type == TxnType.income,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        onTap: () => showTransactionEditor(context, existing: txn),
      ),
    );
  }
}
