import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/widgets/async_widgets.dart';
import 'models.dart';
import 'money_providers.dart';
import 'widgets.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);
    final balances = ref.watch(accountBalancesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Account'),
      ),
      body: AsyncView(
        value: accountsAsync,
        onRetry: () => ref.invalidate(accountsProvider),
        data: (accounts) {
          if (accounts.isEmpty) {
            return const EmptyView(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No accounts',
              subtitle: 'Add a cash, bank, or card account to get started.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: accounts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (_, i) {
              final a = accounts[i];
              final bal = balances[a.id] ?? a.openingBalance;
              return Card(
                child: ListTile(
                  leading: IconBadge(iconName: a.icon, color: a.color),
                  title: Text(a.name),
                  subtitle: Text(a.type),
                  trailing: Text(
                    Fmt.money(bal, a.currency),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: bal < 0
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                  onTap: () => _showEditor(context, ref, existing: a),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showEditor(BuildContext context, WidgetRef ref, {Account? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AccountEditor(existing: existing),
    );
  }
}

class _AccountEditor extends ConsumerStatefulWidget {
  const _AccountEditor({this.existing});
  final Account? existing;

  @override
  ConsumerState<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends ConsumerState<_AccountEditor> {
  late TextEditingController _name;
  late TextEditingController _opening;
  late String _type;
  late String _icon;
  late Color _color;
  bool _saving = false;

  static const _types = ['cash', 'bank', 'card', 'wallet', 'savings'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _opening = TextEditingController(
        text: e == null ? '0' : e.openingBalance.toStringAsFixed(2));
    _type = e?.type ?? 'cash';
    _icon = e?.icon ?? 'wallet';
    _color = Lookup.colorFromHex(e?.color, fallback: Lookup.palette[9]);
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'Enter a name', error: true);
      return;
    }
    setState(() => _saving = true);
    final base = ref.read(baseCurrencyProvider);
    final acct = Account(
      id: widget.existing?.id ?? '',
      name: _name.text.trim(),
      type: _type,
      openingBalance: double.tryParse(_opening.text.trim()) ?? 0,
      currency: widget.existing?.currency ?? base,
      icon: _icon,
      color: Lookup.hexFromColor(_color),
    );
    try {
      final n = ref.read(accountsProvider.notifier);
      if (widget.existing == null) {
        await n.add(acct);
      } else {
        await n.edit(acct);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: 'Delete account?',
        message: 'All its transactions will also be removed.');
    if (ok != true) return;
    try {
      await ref.read(accountsProvider.notifier).remove(widget.existing!.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: widget.existing == null ? 'New account' : 'Edit account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _opening,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true, signed: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d{0,2}')),
            ],
            decoration: const InputDecoration(labelText: 'Opening balance'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              for (final t in _types)
                DropdownMenuItem(value: t, child: Text(t)),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'cash'),
          ),
          const SizedBox(height: 16),
          IconColorPicker(
            iconNames: Lookup.accountIconNames,
            selectedIcon: _icon,
            selectedColor: _color,
            onIcon: (v) => setState(() => _icon = v),
            onColor: (v) => setState(() => _color = v),
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
          if (widget.existing != null)
            TextButton.icon(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label:
                  const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }
}

/// Shared confirm dialog used across the money module.
Future<bool?> confirmDialog(BuildContext context,
    {required String title, required String message}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text(title),
      content: Text(message),
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
}
