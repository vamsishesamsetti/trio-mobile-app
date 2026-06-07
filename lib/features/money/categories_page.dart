import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/widgets/async_widgets.dart';
import 'accounts_page.dart' show confirmDialog;
import 'models.dart';
import 'money_providers.dart';
import 'widgets.dart';

class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(categoriesProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categories'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Expense'),
            Tab(text: 'Income'),
          ]),
        ),
        floatingActionButton: Builder(builder: (context) {
          return FloatingActionButton.extended(
            onPressed: () {
              final kind = DefaultTabController.of(context).index == 0
                  ? TxnType.expense
                  : TxnType.income;
              _showEditor(context, ref, kind: kind);
            },
            icon: const Icon(Icons.add),
            label: const Text('Category'),
          );
        }),
        body: AsyncView(
          value: async,
          onRetry: () => ref.invalidate(categoriesProvider),
          data: (cats) => TabBarView(children: [
            _CategoryList(
                cats: cats.where((c) => c.isExpense).toList(),
                onTap: (c) => _showEditor(context, ref, existing: c)),
            _CategoryList(
                cats: cats.where((c) => !c.isExpense).toList(),
                onTap: (c) => _showEditor(context, ref, existing: c)),
          ]),
        ),
      ),
    );
  }

  void _showEditor(BuildContext context, WidgetRef ref,
      {Category? existing, TxnType kind = TxnType.expense}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CategoryEditor(existing: existing, kind: kind),
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.cats, required this.onTap});
  final List<Category> cats;
  final ValueChanged<Category> onTap;

  @override
  Widget build(BuildContext context) {
    if (cats.isEmpty) {
      return const EmptyView(
          icon: Icons.label_outline, title: 'No categories yet');
    }
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (final c in cats)
          ListTile(
            leading: IconBadge(iconName: c.icon, color: c.color, size: 40),
            title: Text(c.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onTap(c),
          ),
      ],
    );
  }
}

class _CategoryEditor extends ConsumerStatefulWidget {
  const _CategoryEditor({this.existing, required this.kind});
  final Category? existing;
  final TxnType kind;

  @override
  ConsumerState<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends ConsumerState<_CategoryEditor> {
  late TextEditingController _name;
  late String _icon;
  late Color _color;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _icon = e?.icon ?? 'category';
    _color = Lookup.colorFromHex(e?.color, fallback: Lookup.palette.first);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'Enter a name', error: true);
      return;
    }
    setState(() => _saving = true);
    final cat = Category(
      id: widget.existing?.id ?? '',
      name: _name.text.trim(),
      kind: widget.existing?.kind ?? widget.kind,
      icon: _icon,
      color: Lookup.hexFromColor(_color),
    );
    try {
      final n = ref.read(categoriesProvider.notifier);
      if (widget.existing == null) {
        await n.add(cat);
      } else {
        await n.edit(cat);
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
        title: 'Delete category?',
        message: 'Transactions keep their record but lose this category.');
    if (ok != true) return;
    try {
      await ref.read(categoriesProvider.notifier).remove(widget.existing!.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.existing?.kind ?? widget.kind;
    return SheetScaffold(
      title: widget.existing == null
          ? 'New ${kind.name} category'
          : 'Edit category',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 16),
          IconColorPicker(
            iconNames: Lookup.categoryIconNames,
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
