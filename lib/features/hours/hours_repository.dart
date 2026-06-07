import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';
import 'models.dart';

class HoursRepository {
  HoursRepository(this._ref, this._db);
  final Ref _ref;
  final SupabaseClient _db;

  String get _uid => requireUserId(_ref);

  // ---- Projects ----
  Future<List<Project>> fetchProjects() async {
    final rows = await _db.from('projects').select().order('created_at');
    return rows.map((e) => Project.fromMap(e)).toList();
  }

  Future<void> addProject(Project p) =>
      _db.from('projects').insert(p.toInsert(_uid));

  Future<void> updateProject(Project p) => _db
      .from('projects')
      .update(p.toInsert(_uid)..remove('user_id'))
      .eq('id', p.id);

  Future<void> deleteProject(String id) =>
      _db.from('projects').delete().eq('id', id);

  // ---- Time entries ----
  Future<List<TimeEntry>> fetchEntries() async {
    final rows = await _db
        .from('time_entries')
        .select()
        .order('started_at', ascending: false);
    return rows.map((e) => TimeEntry.fromMap(e)).toList();
  }

  /// Starts a timer: inserts an open entry (ended_at null).
  Future<void> startTimer(String projectId, String? task) {
    return _db.from('time_entries').insert({
      'user_id': _uid,
      'project_id': projectId,
      'task': task,
      'started_at': DateTime.now().toUtc().toIso8601String(),
      'billable': true,
    });
  }

  /// Stops a running entry, writing ended_at + computed duration.
  Future<void> stopTimer(TimeEntry entry) {
    final now = DateTime.now();
    return _db.from('time_entries').update({
      'ended_at': now.toUtc().toIso8601String(),
      'duration_seconds': now.difference(entry.startedAt).inSeconds,
    }).eq('id', entry.id);
  }

  Future<void> addManualEntry(TimeEntry e) =>
      _db.from('time_entries').insert(e.toInsert(_uid));

  Future<void> updateEntry(TimeEntry e) => _db
      .from('time_entries')
      .update(e.toInsert(_uid)..remove('user_id'))
      .eq('id', e.id);

  Future<void> deleteEntry(String id) =>
      _db.from('time_entries').delete().eq('id', id);
}

final hoursRepositoryProvider = Provider<HoursRepository>((ref) {
  return HoursRepository(ref, ref.watch(supabaseProvider));
});
