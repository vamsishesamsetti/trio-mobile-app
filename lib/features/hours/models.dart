/// Models for the Hours Tracker. Hand-written, mapping to Postgres rows.
library;

double _toDouble(dynamic v) =>
    v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

class Project {
  final String id;
  final String name;
  final String? client;
  final double hourlyRate;
  final String currency;
  final String? color;
  final bool archived;

  const Project({
    required this.id,
    required this.name,
    required this.client,
    required this.hourlyRate,
    required this.currency,
    required this.color,
    this.archived = false,
  });

  factory Project.fromMap(Map<String, dynamic> m) => Project(
        id: m['id'] as String,
        name: m['name'] as String,
        client: m['client'] as String?,
        hourlyRate: _toDouble(m['hourly_rate']),
        currency: (m['currency'] as String?) ?? 'USD',
        color: m['color'] as String?,
        archived: (m['archived'] as bool?) ?? false,
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        'name': name,
        'client': client,
        'hourly_rate': hourlyRate,
        'currency': currency,
        'color': color,
        'archived': archived,
      };

  Project copyWith({
    String? name,
    String? client,
    double? hourlyRate,
    String? color,
    bool? archived,
  }) =>
      Project(
        id: id,
        name: name ?? this.name,
        client: client ?? this.client,
        hourlyRate: hourlyRate ?? this.hourlyRate,
        currency: currency,
        color: color ?? this.color,
        archived: archived ?? this.archived,
      );
}

class TimeEntry {
  final String id;
  final String projectId;
  final String? task;
  final DateTime startedAt;
  final DateTime? endedAt; // null while the timer is running
  final int? durationSeconds;
  final bool billable;
  final String? note;

  const TimeEntry({
    required this.id,
    required this.projectId,
    required this.task,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
    required this.billable,
    required this.note,
  });

  bool get isRunning => endedAt == null;

  /// Seconds elapsed: stored duration if finished, else live from [startedAt].
  int elapsedSeconds([DateTime? now]) {
    if (durationSeconds != null) return durationSeconds!;
    if (endedAt != null) {
      return endedAt!.difference(startedAt).inSeconds;
    }
    return (now ?? DateTime.now()).difference(startedAt).inSeconds;
  }

  factory TimeEntry.fromMap(Map<String, dynamic> m) => TimeEntry(
        id: m['id'] as String,
        projectId: m['project_id'] as String,
        task: m['task'] as String?,
        startedAt: DateTime.parse(m['started_at'] as String).toLocal(),
        endedAt: m['ended_at'] == null
            ? null
            : DateTime.parse(m['ended_at'] as String).toLocal(),
        durationSeconds: (m['duration_seconds'] as num?)?.toInt(),
        billable: (m['billable'] as bool?) ?? true,
        note: m['note'] as String?,
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        'project_id': projectId,
        'task': task,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt?.toUtc().toIso8601String(),
        'duration_seconds': durationSeconds,
        'billable': billable,
        'note': note,
      };
}
