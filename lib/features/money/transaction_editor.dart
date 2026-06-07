import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/async_widgets.dart';
import 'models.dart';
import 'money_providers.dart';
import 'widgets.dart';

/// Bottom sheet to add or edit a transaction. Pass [existing] to edit.
Future<void> showTransactionEditor(BuildContext context,
    {MoneyTransaction? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (_) => TransactionEditor(existing: existing),
  );
}

class TransactionEditor extends ConsumerStatefulWidget {
  const TransactionEditor({super.key, this.existing});
  final MoneyTransaction? existing;

  @override
  ConsumerState<TransactionEditor> createState() => _TransactionEditorState();
}

class _TransactionEditorState extends ConsumerState<TransactionEditor> {
  late TxnType _type;
  late TextEditingController _amount;
  late TextEditingController _note;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  late DateTime _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? TxnType.expense;
    _amount =
        TextEditingController(text: e == null ? '' : e.amount.toStringAsFixed(2));
    _note = TextEditingController(text: e?.note ?? '');
    _accountId = e?.accountId;
    _toAccountId = e?.transferAccountId;
    _categoryId = e?.categoryId;
    _date = e?.date ?? DateTime.now();
  }

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
    if (_type == TxnType.transfer && _toAccountId == null) {
      showSnack(context, 'Pick a destination account', error: true);
      return;
    }
    if (_type == TxnType.transfer && _toAccountId == _accountId) {
      showSnack(context, 'Choose two different accounts', error: true);
      return;
    }

    setState(() => _saving = true);
    final base = ref.read(baseCurrencyProvider);
    final txn = MoneyTransaction(
      id: widget.existing?.id ?? '',
      accountId: _accountId!,
      categoryId: _type == TxnType.transfer ? null : _categoryId,
      type: _type,
      amount: amount,
      currency: base,
      date: _date,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      transferAccountId: _type == TxnType.transfer ? _toAccountId : null,
    );
    try {
      final notifier = ref.read(transactionsProvider.notifier);
      if (widget.existing == null) {
        await notifier.add(txn);
      } else {
        await notifier.edit(txn);
      }
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
      title: widget.existing == null ? 'New transaction' : 'Edit transaction',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<TxnType>(
            segments: const [
              ButtonSegment(value: TxnType.expense, label: Text('Expense')),
              ButtonSegment(value: TxnType.income, label: Text('Income')),
              ButtonSegment(value: TxnType.transfer, label: Text('Transfer')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() {
              _type = s.first;
              _categoryId = null;
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: widget.existing == null,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixIcon: Icon(Icons.attach_money),
            ),
          ),
          const SizedBox(height: 12),
          _AccountDropdown(
            label: _type == TxnType.transfer ? 'From account' : 'Account',
            accounts: accounts,
            value: _accountId,
            onChanged: (v) => setState(() => _accountId = v),
          ),
          if (_type == TxnType.transfer) ...[
            const SizedBox(height: 12),
            _AccountDropdown(
              label: 'To account',
              accounts: accounts,
              value: _toAccountId,
              onChanged: (v) => setState(() => _toAccountId = v),
            ),
          ] else ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.label_outline),
              ),
              items: [
                for (final c in categories)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
          ],
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: const Text('Date'),
            trailing: Text(
                '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2015),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              prefixIcon: Icon(Icons.notes),
            ),
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

class _AccountDropdown extends StatelessWidget {
  const _AccountDropdown({
    required this.label,
    required this.accounts,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final List<Account> accounts;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
      ),
      items: [
        for (final a in accounts)
          DropdownMenuItem(
            value: a.id,
            child: Row(children: [
              IconBadge(iconName: a.icon, color: a.color, size: 28),
              const SizedBox(width: 8),
              Flexible(child: Text(a.name, overflow: TextOverflow.ellipsis)),
            ]),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
