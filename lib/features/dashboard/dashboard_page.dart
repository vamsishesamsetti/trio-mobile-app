import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/supabase.dart';
import '../hours/hours_providers.dart';
import '../money/money_providers.dart';
import '../split/split_providers.dart';

/// Home dashboard aggregating all three trackers into glanceable cards.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final name = (user?.userMetadata?['display_name'] as String?) ??
        user?.email?.split('@').first ??
        'there';

    final base = ref.watch(baseCurrencyProvider);
    final totalBalance = ref.watch(totalBalanceProvider);
    final monthSummary = ref.watch(monthSummaryProvider);
    final overallSplit = ref.watch(myOverallBalanceProvider);
    final running = ref.watch(runningEntryProvider);
    final week = ref.watch(weekHoursProvider);
    final earnings = ref.watch(totalEarningsProvider);
    final weekHours = week.fold<double>(0, (s, d) => s + d.hours);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.go('/profile'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(transactionsProvider)
            ..invalidate(accountsProvider)
            ..invalidate(groupsProvider)
            ..invalidate(entriesProvider)
            ..invalidate(projectsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Hi, $name 👋',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(Fmt.dateFull(DateTime.now()),
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 20),

            // Money
            _SectionCard(
              icon: Icons.account_balance_wallet,
              color: const Color(0xFF4F6DF5),
              title: 'Money',
              onTap: () => context.go('/money'),
              children: [
                _Metric(
                    label: 'Total balance',
                    value: Fmt.money(totalBalance, base)),
                _Metric(
                  label: 'This month net',
                  value: Fmt.money(monthSummary.net, base, sign: true),
                  valueColor: monthSummary.net >= 0
                      ? const Color(0xFF2E9E5B)
                      : const Color(0xFFE0533D),
                ),
                _Metric(
                    label: 'Income · Expense',
                    value:
                        '${Fmt.money(monthSummary.income, base)} · ${Fmt.money(monthSummary.expense, base)}'),
              ],
            ),
            const SizedBox(height: 12),

            // Split
            _SectionCard(
              icon: Icons.groups,
              color: const Color(0xFF7E57C2),
              title: 'Split',
              onTap: () => context.go('/split'),
              children: [
                _Metric(
                  label: overallSplit.abs() < 0.01
                      ? 'Status'
                      : (overallSplit > 0 ? 'You are owed' : 'You owe'),
                  value: overallSplit.abs() < 0.01
                      ? 'All settled up'
                      : Fmt.money(overallSplit.abs(), base),
                  valueColor: overallSplit.abs() < 0.01
                      ? null
                      : (overallSplit > 0
                          ? const Color(0xFF2E9E5B)
                          : const Color(0xFFE0533D)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Hours
            _SectionCard(
              icon: Icons.timer,
              color: const Color(0xFF26A69A),
              title: 'Hours',
              onTap: () => context.go('/hours'),
              children: [
                if (running != null)
                  const _Metric(
                      label: 'Timer', value: 'Running…', valueColor: Color(0xFF2E9E5B)),
                _Metric(
                    label: 'This week',
                    value: '${weekHours.toStringAsFixed(1)} h'),
                _Metric(
                    label: 'Billable earnings',
                    value: Fmt.money(earnings, base)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
    required this.children,
  });
  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.18),
                    child: Icon(icon, color: color)),
                const SizedBox(width: 12),
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                const Icon(Icons.chevron_right),
              ]),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold, color: valueColor)),
        ],
      ),
    );
  }
}
