import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/widgets/async_widgets.dart';
import 'accounts_page.dart' show confirmDialog;
import 'models.dart';
import 'money_providers.dart';
import 'widgets.dart';

class RecurringPage extends ConsumerWidget {
  const RecurringPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recurringProvider);
    final cats = ref.watch(categoryByIdProvider);
    final accts = ref.watch(accountByIdProvider);
    final base = ref.watch(baseCurrencyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => const _RecurringEditor(),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Rule'),
      ),
      body: AsyncView(
        value: async,
        onRetry: () => ref.invalidate(recurringProvider),
        data: (rules) {
          if (rules.isEmpty) {
            return const EmptyView(
              icon: Icons.repeat,
              title: 'No recurring rules',
              subtitle:
                  'Automate salary, rent, subscriptions. They post automatically when due.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(8),
            children: [
              for (final r in rules)
                Dismissible(
                  key: ValueKey(r.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) => confirmDialog(context,
                      title: 'Delete rule?', message: 'Past entries stay.'),
                  onDismissed: (_) =>
                      ref.read(recurringProvider.notifier).remove(r.id),
                  child: ListTile(
                    leading: Icon(txnTypeIcon(r.type)),
                    title: Text(r.note ?? cats[r.categoryId]?.name ?? 'Rule'),
                    subtitle: Text(
                        '${r.frequency.name} · ${accts[r.accountId]?.name ?? ''} · next ${Fmt.dateMedium(r.nextRunDate)}'),
                    trailing: AmountText(
                      Fmt.money(r.amount, base),
                      positive: r.type == TxnType.income,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RecurringEditor extends ConsumerStatefulWidget {
  const _RecurringEditor();

  @override
  ConsumerState<_RecurringEditor> createState() => _RecurringEditorState();
}

class _RecurringEditorState extends ConsumerState<_RecurringEditor> {
  TxnType _type = TxnType.expense;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _accountId;
  String? _categoryId;
  Frequency _freq = Frequency.monthly;
  DateTime _next = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      showSnack(context, 'Enter a valid amount', error: true);
      return;
    }
    if (_accountId == null) {
      showSnack(context, 'Pick an account', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(recurringProvider.notifier).add(RecurringRule(
            id: '',
            accountId: _accountId!,
            categoryId: _categoryId,
            type: _type,
            amount: amount,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            frequency: _freq,
            nextRunDate: DateTime(_next.year, _next.month, _next.day),
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
    final accounts = ref.watch(accountsProvider).value ?? const [];
    final categories = (ref.watch(categoriesProvider).value ?? const [])
        .where((c) => c.kind == _type)
        .toList();

    return SheetScaffold(
      title: 'New recurring rule',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<TxnType>(
            segments: const [
              ButtonSegment(value: TxnType.expense, label: Text('Expense')),
              ButtonSegment(value: TxnType.income, label: Text('Income')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() {
              _type = s.first;
              _categoryId = null;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            decoration: const InputDecoration(labelText: 'Amount'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _accountId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Account'),
            items: [
              for (final a in accounts)
                DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final c in categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Frequency>(
            initialValue: _freq,
            decoration: const InputDecoration(labelText: 'Frequency'),
            items: [
              for (final f in Frequency.values)
                DropdownMenuItem(value: f, child: Text(f.name)),
            ],
            onChanged: (v) => setState(() => _freq = v ?? Frequency.monthly),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: const Text('Next run'),
            trailing: Text(Fmt.dateMedium(_next)),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _next,
                firstDate: DateTime(2015),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _next = picked);
            },
          ),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
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
