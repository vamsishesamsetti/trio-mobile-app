import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../accounts_page.dart';
import '../categories_page.dart';
import '../export.dart';
import '../money_providers.dart';
import '../recurring_page.dart';
import '../transaction_editor.dart';
import 'budgets_tab.dart';
import 'overview_tab.dart';
import 'transactions_tab.dart';

/// Money Tracker tab: Overview / Transactions / Budgets, with a month
/// selector and management menu.
class MoneyPage extends ConsumerStatefulWidget {
  const MoneyPage({super.key});

  @override
  ConsumerState<MoneyPage> createState() => _MoneyPageState();
}

class _MoneyPageState extends ConsumerState<MoneyPage> {
  @override
  void initState() {
    super.initState();
    // Post any due recurring transactions once when the tab opens.
    Future.microtask(() => ref.read(recurringMaterializerProvider.future));
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(selectedMonthProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Money'),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'accounts':
                    _open(const AccountsPage());
                  case 'categories':
                    _open(const CategoriesPage());
                  case 'recurring':
                    _open(const RecurringPage());
                  case 'export':
                    exportTransactionsCsv(context, ref);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'accounts',
                    child: ListTile(
                        leading: Icon(Icons.account_balance_wallet_outlined),
                        title: Text('Accounts'))),
                PopupMenuItem(
                    value: 'categories',
                    child: ListTile(
                        leading: Icon(Icons.label_outline),
                        title: Text('Categories'))),
                PopupMenuItem(
                    value: 'recurring',
                    child: ListTile(
                        leading: Icon(Icons.repeat),
                        title: Text('Recurring'))),
                PopupMenuItem(
                    value: 'export',
                    child: ListTile(
                        leading: Icon(Icons.ios_share),
                        title: Text('Export CSV'))),
              ],
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Overview'),
            Tab(text: 'Transactions'),
            Tab(text: 'Budgets'),
          ]),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => showTransactionEditor(context),
          child: const Icon(Icons.add),
        ),
        body: Column(
          children: [
            _MonthSelector(
              month: month,
              onPrev: () =>
                  ref.read(selectedMonthProvider.notifier).prev(),
              onNext: () =>
                  ref.read(selectedMonthProvider.notifier).next(),
              onReset: () =>
                  ref.read(selectedMonthProvider.notifier).reset(),
            ),
            const Expanded(
              child: TabBarView(children: [
                OverviewTab(),
                TransactionsTab(),
                BudgetsTab(),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.month,
    required this.onPrev,
    required this.onNext,
    required this.onReset,
  });
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
          GestureDetector(
            onTap: onReset,
            child: Text(Fmt.monthYear(month),
                style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(
              onPressed: onNext, icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }
}
