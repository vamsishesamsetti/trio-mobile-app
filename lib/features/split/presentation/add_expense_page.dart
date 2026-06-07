import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants.dart';
import '../../../core/formatters.dart';
import '../../../core/supabase.dart';
import '../../../core/widgets/async_widgets.dart';
import '../models.dart';
import '../split_engine.dart';
import '../split_providers.dart';

class AddExpensePage extends ConsumerStatefulWidget {
  const AddExpensePage({super.key, required this.groupId, this.existing});
  final String groupId;
  final Expense? existing;

  @override
  ConsumerState<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends ConsumerState<AddExpensePage> {
  final _desc = TextEditingController();
  final _amount = TextEditingController();
  String? _paidBy;
  String _category = 'General';
  DateTime _date = DateTime.now();
  SplitType _type = SplitType.equal;
  bool _saving = false;

  /// Selected participants and their per-type weight inputs.
  final Set<String> _participants = {};
  final Map<String, TextEditingController> _weights = {};

  // Receipt: newly-picked bytes, or an already-uploaded URL when editing.
  Uint8List? _receiptBytes;
  String? _receiptUrl;
  bool _didInitFromExisting = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _desc.text = e.description;
      _amount.text = e.amount.toStringAsFixed(2);
      _paidBy = e.paidBy;
      _category = e.category ?? 'General';
      _date = e.date;
      _type = e.splitType;
      _receiptUrl = e.receiptUrl;
      _participants.addAll(e.splits.map((s) => s.userId));
      // Prefill weights so exact splits round-trip; for %/shares the user can
      // re-enter, but equal/exact reconstruct correctly.
      if (e.splitType == SplitType.exact) {
        for (final s in e.splits) {
          _weightCtrl(s.userId).text = s.owedAmount.toStringAsFixed(2);
        }
      }
      _didInitFromExisting = true;
    } else {
      _paidBy = ref.read(supabaseProvider).auth.currentUser?.id;
    }
  }

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    for (final c in _weights.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _total => double.tryParse(_amount.text.trim()) ?? 0;

  TextEditingController _weightCtrl(String uid) =>
      _weights.putIfAbsent(uid, () => TextEditingController());

  Future<void> _pickReceipt() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _receiptBytes = bytes);
  }

  Map<String, double> _computePreview() {
    final parts = _participants.toList();
    if (parts.isEmpty || _total <= 0) return {};
    final weights = <String, double>{
      for (final p in parts)
        p: double.tryParse(_weightCtrl(p).text.trim()) ?? 0,
    };
    return computeSplitAmounts(
      total: _total,
      type: _type,
      participants: parts,
      weights: weights,
    );
  }

  Future<void> _save(Map<String, String> labels) async {
    if (_desc.text.trim().isEmpty) {
      showSnack(context, 'Enter a description', error: true);
      return;
    }
    if (_total <= 0) {
      showSnack(context, 'Enter a valid amount', error: true);
      return;
    }
    if (_paidBy == null) {
      showSnack(context, 'Pick who paid', error: true);
      return;
    }
    if (_participants.isEmpty) {
      showSnack(context, 'Pick at least one participant', error: true);
      return;
    }
    final cur = ref.read(groupCurrencyProvider(widget.groupId));
    final owed = _computePreview();
    final sumOwed = owed.values.fold<double>(0, (s, v) => s + v);
    if ((sumOwed - _total).abs() > 0.05) {
      showSnack(context,
          'Split (${Fmt.money(sumOwed, cur)}) must equal total (${Fmt.money(_total, cur)})',
          error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final actions = ref.read(splitActionsProvider);
      // Upload a newly-picked receipt first.
      String? receiptUrl = _receiptUrl;
      if (_receiptBytes != null) {
        receiptUrl =
            await actions.uploadReceipt(widget.groupId, _receiptBytes!);
      }

      if (_isEdit) {
        await actions.updateExpense(
          groupId: widget.groupId,
          expenseId: widget.existing!.id,
          paidBy: _paidBy!,
          description: _desc.text.trim(),
          amount: _total,
          currency: cur,
          date: _date,
          splitType: _type,
          category: _category,
          owedByUser: owed,
          receiptUrl: receiptUrl,
        );
      } else {
        await actions.addExpense(
          groupId: widget.groupId,
          paidBy: _paidBy!,
          description: _desc.text.trim(),
          amount: _total,
          currency: cur,
          date: _date,
          splitType: _type,
          category: _category,
          owedByUser: owed,
          receiptUrl: receiptUrl,
        );
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
    final membersAsync = ref.watch(groupMembersProvider(widget.groupId));
    final cur = ref.watch(groupCurrencyProvider(widget.groupId));

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit expense' : 'Add expense')),
      body: AsyncView(
        value: membersAsync,
        data: (members) {
          final registered =
              members.where((m) => m.userId != null).toList();
          final labels = {for (final m in registered) m.userId!: m.label};
          // Default: everyone participates (only for brand-new expenses).
          if (_participants.isEmpty &&
              registered.isNotEmpty &&
              !_didInitFromExisting) {
            _participants.addAll(registered.map((m) => m.userId!));
          }
          final preview = _computePreview();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              TextField(
                controller: _desc,
                decoration: const InputDecoration(
                    labelText: 'Description',
                    prefixIcon: Icon(Icons.description_outlined)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                    labelText: 'Amount', prefixIcon: Icon(Icons.attach_money)),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _paidBy,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Paid by',
                    prefixIcon: Icon(Icons.account_circle_outlined)),
                items: [
                  for (final m in registered)
                    DropdownMenuItem(value: m.userId, child: Text(m.label)),
                ],
                onChanged: (v) => setState(() => _paidBy = v),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _category,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Category'),
                    items: [
                      for (final c in kSplitCategories.keys)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (v) =>
                        setState(() => _category = v ?? 'General'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2015),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                  icon: const Icon(Icons.event),
                  label: Text(Fmt.dateShort(_date)),
                ),
              ]),
              const SizedBox(height: 16),
              Text('Split', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<SplitType>(
                segments: const [
                  ButtonSegment(value: SplitType.equal, label: Text('Equal')),
                  ButtonSegment(value: SplitType.exact, label: Text('Exact')),
                  ButtonSegment(value: SplitType.percent, label: Text('%')),
                  ButtonSegment(
                      value: SplitType.shares, label: Text('Shares')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 12),
              for (final m in registered)
                _ParticipantRow(
                  label: m.label,
                  selected: _participants.contains(m.userId),
                  type: _type,
                  currency: cur,
                  weightController: _weightCtrl(m.userId!),
                  owed: preview[m.userId],
                  onToggle: (v) => setState(() {
                    if (v) {
                      _participants.add(m.userId!);
                    } else {
                      _participants.remove(m.userId!);
                    }
                  }),
                  onWeightChanged: () => setState(() {}),
                ),
              const SizedBox(height: 8),
              _SplitSummary(preview: preview, total: _total, currency: cur),
              const SizedBox(height: 16),
              _ReceiptPicker(
                bytes: _receiptBytes,
                existingUrl: _receiptUrl,
                onPick: _pickReceipt,
                onClear: () => setState(() {
                  _receiptBytes = null;
                  _receiptUrl = null;
                }),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : () => _save(labels),
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4))
                    : Text(_isEdit ? 'Save changes' : 'Save expense'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReceiptPicker extends StatelessWidget {
  const _ReceiptPicker({
    required this.bytes,
    required this.existingUrl,
    required this.onPick,
    required this.onClear,
  });
  final Uint8List? bytes;
  final String? existingUrl;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasImage = bytes != null || existingUrl != null;
    if (!hasImage) {
      return OutlinedButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Attach receipt'),
      );
    }
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: bytes != null
              ? Image.memory(bytes!, width: 64, height: 64, fit: BoxFit.cover)
              : Image.network(existingUrl!,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined)),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Text('Receipt attached')),
        TextButton(onPressed: onPick, child: const Text('Change')),
        IconButton(
            onPressed: onClear, icon: const Icon(Icons.close)),
      ],
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.label,
    required this.selected,
    required this.type,
    required this.currency,
    required this.weightController,
    required this.owed,
    required this.onToggle,
    required this.onWeightChanged,
  });

  final String label;
  final bool selected;
  final SplitType type;
  final String currency;
  final TextEditingController weightController;
  final double? owed;
  final ValueChanged<bool> onToggle;
  final VoidCallback onWeightChanged;

  @override
  Widget build(BuildContext context) {
    final showWeight = selected && type != SplitType.equal;
    final hint = switch (type) {
      SplitType.exact => '\$',
      SplitType.percent => '%',
      SplitType.shares => 'shares',
      SplitType.equal => '',
    };
    return Row(
      children: [
        Expanded(
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: selected,
            onChanged: (v) => onToggle(v ?? false),
            title: Text(label),
            subtitle: selected && owed != null
                ? Text('owes ${Fmt.money(owed!, currency)}')
                : null,
          ),
        ),
        if (showWeight)
          SizedBox(
            width: 90,
            child: TextField(
              controller: weightController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: InputDecoration(hintText: hint, isDense: true),
              onChanged: (_) => onWeightChanged(),
            ),
          ),
      ],
    );
  }
}

class _SplitSummary extends StatelessWidget {
  const _SplitSummary(
      {required this.preview, required this.total, required this.currency});
  final Map<String, double> preview;
  final double total;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final sum = preview.values.fold<double>(0, (s, v) => s + v);
    final ok = (sum - total).abs() < 0.05 && total > 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Allocated ${Fmt.money(sum, currency)} of ${Fmt.money(total, currency)}'),
          Icon(ok ? Icons.check_circle : Icons.error_outline,
              color: ok
                  ? const Color(0xFF2E9E5B)
                  : Theme.of(context).colorScheme.error),
        ],
      ),
    );
  }
}
