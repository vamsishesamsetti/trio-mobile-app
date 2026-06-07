import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/formatters.dart';
import '../models.dart';
import '../money_providers.dart';
import '../transaction_editor.dart';
import '../widgets.dart';

class OverviewTab extends ConsumerWidget {
  const OverviewTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ref.watch(baseCurrencyProvider);
    final summary = ref.watch(monthSummaryProvider);
    final total = ref.watch(totalBalanceProvider);
    final spendByCat = ref.watch(monthSpendByCategoryProvider);
    final cats = ref.watch(categoryByIdProvider);
    final monthTxns = ref.watch(monthTransactionsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(transactionsProvider);
        ref.invalidate(accountsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Net worth across accounts.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('Total balance',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(Fmt.money(total, base),
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _StatCard(
                    label: 'Income',
                    value: Fmt.money(summary.income, base),
                    color: const Color(0xFF2E9E5B),
                    icon: Icons.south_west)),
            const SizedBox(width: 8),
            Expanded(
                child: _StatCard(
                    label: 'Expenses',
                    value: Fmt.money(summary.expense, base),
                    color: const Color(0xFFE0533D),
                    icon: Icons.north_east)),
          ]),
          const SizedBox(height: 8),
          _StatCard(
            label: 'Net this month',
            value: Fmt.money(summary.net, base, sign: true),
            color: summary.net >= 0
                ? const Color(0xFF2E9E5B)
                : const Color(0xFFE0533D),
            icon: Icons.account_balance,
            wide: true,
          ),
          const SizedBox(height: 16),
          _SpendingChart(spendByCat: spendByCat, cats: cats, base: base),
          const SizedBox(height: 16),
          const _TrendChart(),
          const SizedBox(height: 16),
          Text('Recent', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          if (monthTxns.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No transactions this month')),
            )
          else
            for (final t in monthTxns.take(5))
              _MiniTxnTile(txn: t, cats: cats, base: base),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.wide = false,
  });
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment:
              wide ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.18),
                  child: Icon(icon, color: color, size: 20)),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context).textTheme.labelMedium),
                  if (!wide)
                    Text(value,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ]),
            if (wide)
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

class _SpendingChart extends StatelessWidget {
  const _SpendingChart(
      {required this.spendByCat, required this.cats, required this.base});
  final Map<String, double> spendByCat;
  final Map<String, Category> cats;
  final String base;

  @override
  Widget build(BuildContext context) {
    if (spendByCat.isEmpty) return const SizedBox.shrink();
    final entries = spendByCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalSpend = entries.fold<double>(0, (s, e) => s + e.value);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Spending by category',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 44,
                  sections: [
                    for (final e in entries.take(8))
                      PieChartSectionData(
                        value: e.value,
                        color: Lookup.colorFromHex(cats[e.key]?.color,
                            fallback: Colors.grey),
                        title:
                            '${(e.value / totalSpend * 100).round()}%',
                        radius: 50,
                        titleStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final e in entries.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Lookup.colorFromHex(cats[e.key]?.color,
                          fallback: Colors.grey),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(cats[e.key]?.name ?? 'Uncategorized',
                          overflow: TextOverflow.ellipsis)),
                  Text(Fmt.money(e.value, base)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _TrendChart extends ConsumerWidget {
  const _TrendChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buckets = ref.watch(trendProvider);
    final base = ref.watch(baseCurrencyProvider);
    final maxVal = buckets.fold<double>(
        1,
        (m, b) =>
            [m, b.income, b.expense].reduce((a, c) => a > c ? a : c));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('6-month trend',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: maxVal * 1.2,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= buckets.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                                Fmt.dateShort(buckets[i].month)
                                    .split(' ')
                                    .first,
                                style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < buckets.length; i++)
                      BarChartGroupData(x: i, barRods: [
                        BarChartRodData(
                            toY: buckets[i].income,
                            color: const Color(0xFF2E9E5B),
                            width: 7,
                            borderRadius: BorderRadius.circular(2)),
                        BarChartRodData(
                            toY: buckets[i].expense,
                            color: const Color(0xFFE0533D),
                            width: 7,
                            borderRadius: BorderRadius.circular(2)),
                      ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _legendDot(const Color(0xFF2E9E5B), 'Income'),
              const SizedBox(width: 16),
              _legendDot(const Color(0xFFE0533D), 'Expense'),
            ]),
            const SizedBox(height: 4),
            Center(
              child: Text('Base currency: $base',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color c, String label) => Row(children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);
}

class _MiniTxnTile extends StatelessWidget {
  const _MiniTxnTile(
      {required this.txn, required this.cats, required this.base});
  final MoneyTransaction txn;
  final Map<String, Category> cats;
  final String base;

  @override
  Widget build(BuildContext context) {
    final cat = txn.categoryId == null ? null : cats[txn.categoryId];
    final isTransfer = txn.type == TxnType.transfer;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: IconBadge(
          iconName: isTransfer ? 'swap' : cat?.icon,
          color: cat?.color,
          size: 40),
      title: Text(isTransfer
          ? 'Transfer'
          : (cat?.name ?? txn.note ?? 'Transaction')),
      subtitle: Text(Fmt.dateMedium(txn.date)),
      trailing: AmountText(
        Fmt.money(txn.amount, base),
        positive: txn.type == TxnType.income,
      ),
      onTap: () => showTransactionEditor(context, existing: txn),
    );
  }
}
