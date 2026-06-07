import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/widgets/async_widgets.dart';
import '../money/accounts_page.dart' show confirmDialog;
import '../profile/profile_repository.dart';
import 'hours_providers.dart';
import 'models.dart';

class ProjectsPage extends ConsumerWidget {
  const ProjectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(projectsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editor(context),
        icon: const Icon(Icons.add),
        label: const Text('Project'),
      ),
      body: AsyncView(
        value: async,
        onRetry: () => ref.invalidate(projectsProvider),
        data: (projects) {
          if (projects.isEmpty) {
            return const EmptyView(
              icon: Icons.work_outline,
              title: 'No projects',
              subtitle: 'Add a project with an hourly rate to track time.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(8),
            children: [
              for (final p in projects)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Lookup.colorFromHex(p.color),
                    child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(p.name),
                  subtitle: Text([
                    if (p.client != null && p.client!.isNotEmpty) p.client!,
                    '${Fmt.money(p.hourlyRate, p.currency)}/hr',
                  ].join(' · ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editor(context, existing: p),
                ),
            ],
          );
        },
      ),
    );
  }

  void _editor(BuildContext context, {Project? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProjectEditor(existing: existing),
    );
  }
}

class _ProjectEditor extends ConsumerStatefulWidget {
  const _ProjectEditor({this.existing});
  final Project? existing;

  @override
  ConsumerState<_ProjectEditor> createState() => _ProjectEditorState();
}

class _ProjectEditorState extends ConsumerState<_ProjectEditor> {
  late TextEditingController _name;
  late TextEditingController _client;
  late TextEditingController _rate;
  late Color _color;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _client = TextEditingController(text: e?.client ?? '');
    _rate = TextEditingController(
        text: e == null ? '' : e.hourlyRate.toStringAsFixed(2));
    _color = Lookup.colorFromHex(e?.color, fallback: Lookup.palette[5]);
  }

  @override
  void dispose() {
    _name.dispose();
    _client.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'Enter a name', error: true);
      return;
    }
    setState(() => _saving = true);
    final p = Project(
      id: widget.existing?.id ?? '',
      name: _name.text.trim(),
      client: _client.text.trim().isEmpty ? null : _client.text.trim(),
      hourlyRate: double.tryParse(_rate.text.trim()) ?? 0,
      currency: widget.existing?.currency ??
          ref.read(displayCurrencyProvider),
      color: Lookup.hexFromColor(_color),
    );
    try {
      final n = ref.read(projectsProvider.notifier);
      if (widget.existing == null) {
        await n.add(p);
      } else {
        await n.edit(p);
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
        title: 'Delete project?',
        message: 'All time entries for it will be removed.');
    if (ok != true) return;
    await ref.read(projectsProvider.notifier).remove(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'New project' : 'Edit project',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Project name')),
            const SizedBox(height: 12),
            TextField(
                controller: _client,
                decoration:
                    const InputDecoration(labelText: 'Client (optional)')),
            const SizedBox(height: 12),
            TextField(
              controller: _rate,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: const InputDecoration(
                  labelText: 'Hourly rate', prefixIcon: Icon(Icons.attach_money)),
            ),
            const SizedBox(height: 16),
            const Text('Color'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in Lookup.palette)
                  InkWell(
                    onTap: () => setState(() => _color = c),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color.toARGB32() == c.toARGB32()
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
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
                label: const Text('Delete',
                    style: TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
