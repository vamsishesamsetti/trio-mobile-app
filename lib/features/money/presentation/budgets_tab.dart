import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/widgets/async_widgets.dart';
import '../models.dart';
import '../money_providers.dart';
import '../widgets.dart';

class BudgetsTab extends ConsumerWidget {
  const BudgetsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(budgetProgressProvider);
    final base = ref.watch(baseCurrencyProvider);

    return Stack(
      children: [
        if (progress.isEmpty)
          const EmptyView(
            icon: Icons.savings_outlined,
            title: 'No budgets',
            subtitle: 'Set monthly limits per category to track spending.',
          )
        else
          ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
            children: [
              for (final p in progress) _BudgetCard(p: p, base: base),
            ],
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'budgetFab',
            onPressed: () => _showEditor(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Budget'),
          ),
        ),
      ],
    );
  }

  void _showEditor(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BudgetEditor(),
    );
  }
}

class _BudgetCard extends ConsumerWidget {
  const _BudgetCard({required this.p, required this.base});
  final BudgetProgress p;
  final String base;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratio = p.ratio.clamp(0.0, 1.0);
    final color = p.over
        ? Theme.of(context).colorScheme.error
        : (ratio > 0.8 ? Colors.orange : Theme.of(context).colorScheme.primary);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              IconBadge(
                  iconName: p.category?.icon,
                  color: p.category?.color,
                  size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.category?.name ?? 'Category',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(p.budget.period.name,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () =>
                    ref.read(budgetsProvider.notifier).remove(p.budget.id),
              ),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 10,
                color: color,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${Fmt.money(p.spent, base)} of ${Fmt.money(p.budget.amount, base)}'),
                Text(
                  p.over
                      ? 'Over by ${Fmt.money(-p.remaining, base)}'
                      : '${Fmt.money(p.remaining, base)} left',
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetEditor extends ConsumerStatefulWidget {
  const _BudgetEditor();

  @override
  ConsumerState<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends ConsumerState<_BudgetEditor> {
  final _amount = TextEditingController();
  String? _categoryId;
  BudgetPeriod _period = BudgetPeriod.monthly;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      showSnack(context, 'Enter a valid amount', error: true);
      return;
    }
    if (_categoryId == null) {
      showSnack(context, 'Pick a category', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(budgetsProvider.notifier).add(Budget(
            id: '',
            categoryId: _categoryId!,
            amount: amount,
            period: _period,
            startDate: DateTime.now(),
          ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expenseCats = (ref.watch(categoriesProvider).value ?? const [])
        .where((c) => c.isExpense)
        .toList();
    return SheetScaffold(
      title: 'New budget',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final c in expenseCats)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            decoration: const InputDecoration(labelText: 'Limit amount'),
          ),
          const SizedBox(height: 12),
          SegmentedButton<BudgetPeriod>(
            segments: const [
              ButtonSegment(value: BudgetPeriod.weekly, label: Text('Weekly')),
              ButtonSegment(
                  value: BudgetPeriod.monthly, label: Text('Monthly')),
              ButtonSegment(value: BudgetPeriod.yearly, label: Text('Yearly')),
            ],
            selected: {_period},
            onSelectionChanged: (s) => setState(() => _period = s.first),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
