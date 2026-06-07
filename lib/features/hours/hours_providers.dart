import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'hours_repository.dart';
import 'models.dart';

// ---------------------------------------------------------------------------
// Projects
// ---------------------------------------------------------------------------
class ProjectsNotifier extends AsyncNotifier<List<Project>> {
  HoursRepository get _repo => ref.read(hoursRepositoryProvider);

  @override
  Future<List<Project>> build() => _repo.fetchProjects();

  Future<void> _reload() async {
    state = await AsyncValue.guard(_repo.fetchProjects);
  }

  Future<void> add(Project p) async {
    await _repo.addProject(p);
    await _reload();
  }

  Future<void> edit(Project p) async {
    await _repo.updateProject(p);
    await _reload();
  }

  Future<void> remove(String id) async {
    await _repo.deleteProject(id);
    await _reload();
    ref.invalidate(entriesProvider);
  }
}

final projectsProvider =
    AsyncNotifierProvider<ProjectsNotifier, List<Project>>(
        ProjectsNotifier.new);

final projectByIdProvider = Provider<Map<String, Project>>((ref) {
  final list = ref.watch(projectsProvider).value ?? const [];
  return {for (final p in list) p.id: p};
});

// ---------------------------------------------------------------------------
// Time entries
// ---------------------------------------------------------------------------
class EntriesNotifier extends AsyncNotifier<List<TimeEntry>> {
  HoursRepository get _repo => ref.read(hoursRepositoryProvider);

  @override
  Future<List<TimeEntry>> build() => _repo.fetchEntries();

  Future<void> _reload() async {
    state = await AsyncValue.guard(_repo.fetchEntries);
  }

  Future<void> start(String projectId, String? task) async {
    await _repo.startTimer(projectId, task);
    await _reload();
  }

  Future<void> stop(TimeEntry entry) async {
    await _repo.stopTimer(entry);
    await _reload();
  }

  Future<void> addManual(TimeEntry e) async {
    await _repo.addManualEntry(e);
    await _reload();
  }

  Future<void> edit(TimeEntry e) async {
    await _repo.updateEntry(e);
    await _reload();
  }

  Future<void> remove(String id) async {
    await _repo.deleteEntry(id);
    await _reload();
  }
}

final entriesProvider =
    AsyncNotifierProvider<EntriesNotifier, List<TimeEntry>>(
        EntriesNotifier.new);

/// The single running entry, if any.
final runningEntryProvider = Provider<TimeEntry?>((ref) {
  final entries = ref.watch(entriesProvider).value ?? const [];
  for (final e in entries) {
    if (e.isRunning) return e;
  }
  return null;
});

/// Emits every second so the running-timer UI updates live. Only ticks while a
/// timer is running, to avoid needless rebuilds.
final tickerProvider = StreamProvider<DateTime>((ref) {
  final running = ref.watch(runningEntryProvider);
  if (running == null) {
    return Stream.value(DateTime.now());
  }
  return Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
});

// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------
class ProjectTotal {
  final Project project;
  final int seconds;
  final double earnings;
  const ProjectTotal(this.project, this.seconds, this.earnings);
  double get hours => seconds / 3600.0;
}

/// Totals per project: total time + billable-only earnings (hours × rate).
final projectTotalsProvider = Provider<List<ProjectTotal>>((ref) {
  final entries = ref.watch(entriesProvider).value ?? const [];
  final projects = ref.watch(projectByIdProvider);
  final now = ref.watch(tickerProvider).value ?? DateTime.now();

  final totalSecs = <String, int>{};
  final billableSecs = <String, int>{};
  for (final entry in entries) {
    final s = entry.elapsedSeconds(now);
    totalSecs[entry.projectId] = (totalSecs[entry.projectId] ?? 0) + s;
    if (entry.billable) {
      billableSecs[entry.projectId] =
          (billableSecs[entry.projectId] ?? 0) + s;
    }
  }

  final result = <ProjectTotal>[];
  totalSecs.forEach((pid, secs) {
    final p = projects[pid];
    if (p == null) return;
    final earnings = (billableSecs[pid] ?? 0) / 3600.0 * p.hourlyRate;
    result.add(ProjectTotal(p, secs, earnings));
  });
  result.sort((a, b) => b.seconds.compareTo(a.seconds));
  return result;
});

/// Hours per day for the last 7 days (for the bar chart), oldest first.
class DayHours {
  final DateTime day;
  final double hours;
  const DayHours(this.day, this.hours);
}

final weekHoursProvider = Provider<List<DayHours>>((ref) {
  final entries = ref.watch(entriesProvider).value ?? const [];
  final now = ref.watch(tickerProvider).value ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final result = <DayHours>[];
  for (var i = 6; i >= 0; i--) {
    final day = today.subtract(Duration(days: i));
    var secs = 0;
    for (final entry in entries) {
      final s = entry.startedAt;
      if (s.year == day.year && s.month == day.month && s.day == day.day) {
        secs += entry.elapsedSeconds(now);
      }
    }
    result.add(DayHours(day, secs / 3600.0));
  }
  return result;
});

final totalEarningsProvider = Provider<double>((ref) {
  return ref
      .watch(projectTotalsProvider)
      .fold<double>(0, (s, t) => s + t.earnings);
});
