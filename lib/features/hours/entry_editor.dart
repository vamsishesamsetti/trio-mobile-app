import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/widgets/async_widgets.dart';
import 'hours_providers.dart';
import 'models.dart';

/// Sheet for adding or editing a manual time entry (start + end times).
Future<void> showEntryEditor(BuildContext context, {TimeEntry? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EntryEditor(existing: existing),
  );
}

class _EntryEditor extends ConsumerStatefulWidget {
  const _EntryEditor({this.existing});
  final TimeEntry? existing;

  @override
  ConsumerState<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends ConsumerState<_EntryEditor> {
  String? _projectId;
  late TextEditingController _task;
  late TextEditingController _note;
  late DateTime _start;
  late DateTime _end;
  bool _billable = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _projectId = e?.projectId;
    _task = TextEditingController(text: e?.task ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _start = e?.startedAt ?? DateTime.now().subtract(const Duration(hours: 1));
    _end = e?.endedAt ?? DateTime.now();
    _billable = e?.billable ?? true;
  }

  @override
  void dispose() {
    _task.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _durationSeconds => _end.difference(_start).inSeconds;

  Future<void> _pick(bool isStart) async {
    final initial = isStart ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _start = dt;
      } else {
        _end = dt;
      }
    });
  }

  Future<void> _save() async {
    if (_projectId == null) {
      showSnack(context, 'Pick a project', error: true);
      return;
    }
    if (_durationSeconds <= 0) {
      showSnack(context, 'End must be after start', error: true);
      return;
    }
    setState(() => _saving = true);
    final entry = TimeEntry(
      id: widget.existing?.id ?? '',
      projectId: _projectId!,
      task: _task.text.trim().isEmpty ? null : _task.text.trim(),
      startedAt: _start,
      endedAt: _end,
      durationSeconds: _durationSeconds,
      billable: _billable,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    try {
      final n = ref.read(entriesProvider.notifier);
      if (widget.existing == null) {
        await n.addManual(entry);
      } else {
        await n.edit(entry);
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
    final projects = ref.watch(projectsProvider).value ?? const [];
    // Preselect a project (the only one, or the first) when none is chosen.
    _projectId ??= projects.isNotEmpty ? projects.first.id : null;
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
            Text(widget.existing == null ? 'Add time' : 'Edit entry',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _projectId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Project'),
              items: [
                for (final p in projects)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => _projectId = v),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _task,
                decoration:
                    const InputDecoration(labelText: 'Task (optional)')),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.play_arrow),
              title: const Text('Start'),
              trailing: Text(Fmt.dateTime(_start)),
              onTap: () => _pick(true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.stop),
              title: const Text('End'),
              trailing: Text(Fmt.dateTime(_end)),
              onTap: () => _pick(false),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text('Duration: ${Fmt.hm(_durationSeconds.clamp(0, 1 << 31))}',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _billable,
              onChanged: (v) => setState(() => _billable = v),
              title: const Text('Billable'),
            ),
            TextField(
                controller: _note,
                decoration:
                    const InputDecoration(labelText: 'Note (optional)')),
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
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
