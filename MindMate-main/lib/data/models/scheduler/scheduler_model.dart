import '../journal/journal_model.dart' show formatDateOnly, parseDateOnly;

/// Mirrors `app.schemas.scheduler.SchedulerEntryRead` — one saved row, as
/// returned nested inside a [SchedulerDay] from both `GET` and
/// `PUT /scheduler/{entry_date}` (see PHASE11B and
/// `backend/app/schemas/scheduler.py`).
///
/// `scheduledTime` is kept exactly as the backend sends it — a plain,
/// zero-padded `"HH:MM"` string, never a Dart `TimeOfDay`/`Duration` — the
/// backend itself stores it as a bare string with no timezone or seconds
/// concept (see `backend/app/models/scheduler.py`'s module doc). Converting
/// between this and the app's pre-existing `"H.MM"`/`"HH.MM"` UI convention
/// happens only at the Scheduler UI boundary, via [dotTimeToColon]/
/// [colonTimeToDot] below — nothing in this model or in
/// `SchedulerRepository` ever sees the dotted form.
class SchedulerEntry {
  const SchedulerEntry({
    required this.id,
    required this.entryDate,
    required this.scheduledTime,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Date-only — parsed with [parseDateOnly], not `DateTime.parse` directly,
  /// for the same local-vs-UTC reason documented on `JournalModel.entryDate`.
  final DateTime entryDate;

  /// Always exactly `"HH:MM"`, 24-hour, zero-padded (validated server-side —
  /// see `backend/app/schemas/scheduler.py`'s `_TIME_PATTERN`).
  final String scheduledTime;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory SchedulerEntry.fromJson(Map<String, dynamic> json) {
    return SchedulerEntry(
      id: json['id'] as String,
      entryDate: parseDateOnly(json['entry_date'] as String),
      scheduledTime: json['scheduled_time'] as String,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'entry_date': formatDateOnly(entryDate),
    'scheduled_time': scheduledTime,
    'description': description,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

/// Mirrors `app.schemas.scheduler.SchedulerDayRead` — the full response of
/// both `GET` and `PUT /scheduler/{entry_date}`: every row currently saved
/// for that date, ordered by `scheduled_time`. An empty [items] list means
/// nothing is scheduled for that date — never an error (see PHASE11B and
/// the backend route's own docstring).
class SchedulerDay {
  const SchedulerDay({required this.entryDate, required this.items});

  final DateTime entryDate;
  final List<SchedulerEntry> items;

  factory SchedulerDay.fromJson(Map<String, dynamic> json) {
    return SchedulerDay(
      entryDate: parseDateOnly(json['entry_date'] as String),
      items: (json['items'] as List<dynamic>)
          .map((item) => SchedulerEntry.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'entry_date': formatDateOnly(entryDate),
    'items': items.map((item) => item.toJson()).toList(),
  };
}

/// Mirrors `app.schemas.scheduler.SchedulerEntryInput` — one row of a
/// `PUT /scheduler/{entry_date}` request body. Unlike [SchedulerEntry], this
/// carries no `id`/timestamps: the backend assigns/derives those, and a
/// whole-day PUT is a full replace, not an addressed-by-id update (see
/// `SchedulerDayUpdate`'s docstring on the backend).
class SchedulerRowInput {
  const SchedulerRowInput({required this.scheduledTime, this.description});

  /// Must already be `"HH:MM"` — convert a UI-entered `"H.MM"`/`"HH.MM"`
  /// string with [dotTimeToColon] before constructing this.
  final String scheduledTime;
  final String? description;

  Map<String, dynamic> toJson() => {'scheduled_time': scheduledTime, 'description': description};
}

/// Converts a UI time string in this app's existing `"H.MM"`/`"HH.MM"`
/// convention (as produced by `scheduler_details_page.dart`'s time picker
/// and `homepage.dart`'s `_getNextAvailableTime`) into the exact
/// zero-padded `"HH:MM"` the backend requires.
///
/// Returns `null` — rather than throwing — for a blank or unparseable
/// [value], so callers can treat that uniformly as "this row has no time"
/// (PHASE11B: a blank-time row is never submitted in a PUT).
String? dotTimeToColon(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final parts = trimmed.split('.');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Converts a screen's UI rows (`{'time': ..., 'desc': ...}`, in this app's
/// existing `"H.MM"`/`"HH.MM"` convention) into the `PUT` payload shape,
/// applying the exact rules PHASE11B requires:
///
/// - A row whose time is blank/unparseable is dropped — never submitted
///   (`dotTimeToColon` returns `null` for it).
/// - A blank/missing description is sent as `null`, but the row itself is
///   kept — a blank description is still a valid row, only a blank time
///   is not.
///
/// Returns `null` if two or more rows resolve to the same backend
/// `"HH:MM"` time. Callers (`scheduler_details_page.dart`'s `_save`) must
/// treat `null` as "refuse to save, and tell the user why" rather than
/// silently keeping only one of the colliding rows — exactly the old Hive
/// `Map<String, String>` scheme's bug (two rows for the same time
/// silently overwrote one another; see the PHASE11 audit report) that
/// this function exists to prevent from ever reaching the backend.
List<SchedulerRowInput>? buildSchedulerRows(List<Map<String, String>> uiRows) {
  final rows = <SchedulerRowInput>[];
  final seenTimes = <String>{};
  for (final row in uiRows) {
    final colonTime = dotTimeToColon(row['time'] ?? '');
    if (colonTime == null) continue; // blank/unset time — not submitted
    if (!seenTimes.add(colonTime)) return null; // duplicate time — refuse the whole save
    final desc = row['desc'];
    rows.add(SchedulerRowInput(scheduledTime: colonTime, description: (desc == null || desc.isEmpty) ? null : desc));
  }
  return rows;
}

/// The inverse of [dotTimeToColon] — converts the backend's `"HH:MM"` back
/// into this app's existing `"HH.MM"` UI convention, so a row loaded from
/// the backend displays identically to one just picked via the in-app time
/// picker. Returns [value] unchanged if it isn't in the expected shape,
/// rather than throwing.
String colonTimeToDot(String value) {
  final parts = value.split(':');
  if (parts.length != 2) return value;
  return '${parts[0]}.${parts[1]}';
}
