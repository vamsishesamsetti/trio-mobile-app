import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/formatters.dart';
import '../../../core/widgets/async_widgets.dart';
import '../../profile/profile_repository.dart';
import '../entry_editor.dart';
import '../hours_providers.dart';
import '../models.dart';
import '../projects_page.dart';

class HoursPage extends ConsumerWidget {
  const HoursPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Hours'),
          actions: [
            IconButton(
              tooltip: 'Projects',
              icon: const Icon(Icons.folder_outlined),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProjectsPage())),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Timer'),
            Tab(text: 'Timesheet'),
            Tab(text: 'Reports'),
          ]),
        ),
        body: const TabBarView(children: [
          _TimerTab(),
          _TimesheetTab(),
          _ReportsTab(),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Timer tab
// ---------------------------------------------------------------------------
class _TimerTab extends ConsumerStatefulWidget {
  const _TimerTab();

  @override
  ConsumerState<_TimerTab> createState() => _TimerTabState();
}

class _TimerTabState extends ConsumerState<_TimerTab> {
  String? _projectId;
  final _task = TextEditingController();

  @override
  void dispose() {
    _task.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = ref.watch(runningEntryProvider);
    final now = ref.watch(tickerProvider).value ?? DateTime.now();
    final projects = ref.watch(projectsProvider).value ?? const [];
    final projectsById = ref.watch(projectByIdProvider);

    if (running != null) {
      final project = projectsById[running.projectId];
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(project?.name ?? 'Project',
                  style: Theme.of(context).textTheme.titleLarge),
              if (running.task != null && running.task!.isNotEmpty)
                Text(running.task!,
                    style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 24),
              Text(
                Fmt.clock(running.elapsedSeconds(now)),
                style: const TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 8),
              Text('Started ${Fmt.time(running.startedAt)}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 32),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE0533D),
                    minimumSize: const Size(220, 56)),
                onPressed: () =>
                    ref.read(entriesProvider.notifier).stop(running),
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ],
          ),
        ),
      );
    }

    if (projects.isEmpty) {
      return EmptyView(
        icon: Icons.work_outline,
        title: 'No projects yet',
        subtitle: 'Create a project to start tracking time.',
        action: FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProjectsPage())),
          icon: const Icon(Icons.add),
          label: const Text('New project'),
        ),
      );
    }

    _projectId ??= projects.first.id;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Start a timer',
            style: Theme.of(context).textTheme.titleMedium),
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
          decoration: const InputDecoration(
              labelText: 'What are you working on? (optional)'),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: () {
            ref.read(entriesProvider.notifier).start(
                _projectId!, _task.text.trim().isEmpty ? null : _task.text.trim());
            _task.clear();
          },
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => showEntryEditor(context),
          icon: const Icon(Icons.edit_calendar),
          label: const Text('Add time manually'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Timesheet tab
// ---------------------------------------------------------------------------
class _TimesheetTab extends ConsumerWidget {
  const _TimesheetTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entriesProvider);
    final projects = ref.watch(projectByIdProvider);
    final now = ref.watch(tickerProvider).value ?? DateTime.now();

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'tsFab',
        onPressed: () => showEntryEditor(context),
        child: const Icon(Icons.add),
      ),
      body: AsyncView(
        value: async,
        onRetry: () => ref.invalidate(entriesProvider),
        data: (entries) {
          final finished = entries.where((e) => !e.isRunning).toList();
          if (finished.isEmpty) {
            return const EmptyView(
                icon: Icons.timer_outlined,
                title: 'No time logged',
                subtitle: 'Start a timer or add an entry manually.');
          }
          // Group by day.
          final grouped = <String, List<TimeEntry>>{};
          for (final e in finished) {
            final key = e.startedAt.toIso8601String().split('T').first;
            grouped.putIfAbsent(key, () => []).add(e);
          }
          final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
            itemCount: days.length,
            itemBuilder: (_, i) {
              final items = grouped[days[i]]!;
              final daySecs =
                  items.fold<int>(0, (s, e) => s + e.elapsedSeconds(now));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(Fmt.dateFull(DateTime.parse(days[i])),
                            style: Theme.of(context).textTheme.labelLarge),
                        Text(Fmt.hm(daySecs),
                            style: Theme.of(context).textTheme.labelLarge),
                      ],
                    ),
                  ),
                  for (final e in items)
                    Dismissible(
                      key: ValueKey(e.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Colors.red,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) =>
                          ref.read(entriesProvider.notifier).remove(e.id),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Lookup.colorFromHex(
                              projects[e.projectId]?.color),
                          radius: 6,
                        ),
                        title: Text(projects[e.projectId]?.name ?? 'Project'),
                        subtitle: Text([
                          if (e.task != null && e.task!.isNotEmpty) e.task!,
                          '${Fmt.time(e.startedAt)}–${e.endedAt != null ? Fmt.time(e.endedAt!) : ''}',
                          if (!e.billable) 'non-billable',
                        ].join(' · ')),
                        trailing: _EntryTrailing(
                          seconds: e.elapsedSeconds(now),
                          earnings: e.billable
                              ? (e.elapsedSeconds(now) / 3600.0) *
                                  (projects[e.projectId]?.hourlyRate ?? 0)
                              : 0,
                          currency:
                              projects[e.projectId]?.currency ?? 'USD',
                        ),
                        onTap: () => showEntryEditor(context, existing: e),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Trailing block for a timesheet row: duration on top, earnings beneath.
class _EntryTrailing extends StatelessWidget {
  const _EntryTrailing({
    required this.seconds,
    required this.earnings,
    required this.currency,
  });
  final int seconds;
  final double earnings;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(Fmt.hm(seconds),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        if (earnings > 0)
          Text(Fmt.money(earnings, currency),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF2E9E5B),
                  fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reports tab
// ---------------------------------------------------------------------------
class _ReportsTab extends ConsumerWidget {
  const _ReportsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(projectTotalsProvider);
    final week = ref.watch(weekHoursProvider);
    final totalEarnings = ref.watch(totalEarningsProvider);
    final cur = ref.watch(displayCurrencyProvider);
    final maxHours =
        week.fold<double>(1, (m, d) => d.hours > m ? d.hours : m);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('Billable earnings',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(Fmt.money(totalEarnings, cur),
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This week',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                SizedBox(
                  height: 160,
                  child: BarChart(
                    BarChartData(
                      maxY: maxHours * 1.2,
                      alignment: BarChartAlignment.spaceAround,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= week.length) {
                                return const SizedBox.shrink();
                              }
                              const wd = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                    wd[week[i].day.weekday - 1],
                                    style: const TextStyle(fontSize: 11)),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < week.length; i++)
                          BarChartGroupData(x: i, barRods: [
                            BarChartRodData(
                              toY: week[i].hours,
                              color: Theme.of(context).colorScheme.primary,
                              width: 16,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('By project', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (totals.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: Text('No time logged yet')),
          )
        else
          for (final t in totals)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                    backgroundColor: Lookup.colorFromHex(t.project.color),
                    radius: 8),
                title: Text(t.project.name),
                subtitle: Text('${t.hours.toStringAsFixed(1)} h'
                    '${t.project.hourlyRate > 0 ? ' · ${Fmt.money(t.project.hourlyRate, t.project.currency)}/hr' : ''}'),
                trailing: Text(Fmt.money(t.earnings, t.project.currency),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
      ],
    );
  }
}
