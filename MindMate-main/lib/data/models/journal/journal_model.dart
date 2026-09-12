/// Mirrors `app.schemas.journal.JournalRead` — the shape returned by every
/// `/journals` endpoint (see PHASE8 audit report, Section H). Field names
/// translate one specific way from the old Firestore doc this replaces:
/// `description` (the Firestore field, and the name `journal_page.dart`'s UI
/// still uses) is `content` on the backend — see the audit report, Section
/// I/Section G — that translation happens once, here and in
/// `JournalRepository`, so nothing above the repository layer needs to know
/// about it.
///
/// No code generation is used, matching every other model under
/// `lib/data/models` (see `token_response_model.dart`, `user_model.dart`).
class JournalModel {
  const JournalModel({
    required this.id,
    required this.userId,
    required this.entryDate,
    this.title,
    this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;

  /// Date-only — the calendar day this entry belongs to, with no
  /// time-of-day and no timezone attached. Parsed from the backend's
  /// `"YYYY-MM-DD"` string with [parseDateOnly] rather than `DateTime.parse`
  /// directly — see that function's doc for why.
  final DateTime entryDate;
  final String? title;
  final String? content;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory JournalModel.fromJson(Map<String, dynamic> json) {
    return JournalModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      entryDate: parseDateOnly(json['entry_date'] as String),
      title: json['title'] as String?,
      content: json['content'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'entry_date': formatDateOnly(entryDate),
    'title': title,
    'content': content,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

/// Formats a [DateTime] as the date-only `YYYY-MM-DD` string the backend's
/// `entry_date`/`start_date`/`end_date` fields expect — local calendar
/// fields only (`.year`/`.month`/`.day`), the same approach
/// `journal_page.dart`'s pre-existing `_dateKey` used for its Firestore doc
/// ids. Deliberately not `toIso8601String()`, which would add a
/// time-of-day (and, for a UTC `DateTime`, a trailing `Z`) the backend's
/// `date`-typed fields don't parse as a bare date.
String formatDateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Parses a date-only `YYYY-MM-DD` string into a local, time-of-day-free
/// [DateTime] by reading the calendar fields directly, rather than via
/// `DateTime.parse`.
///
/// This matters because `DateTime.parse` treats a bare date string (with no
/// time component) as UTC midnight, while every other date already in this
/// app (`DateTime.now()`, the old `_dateKey`) is local. Parsing `entry_date`
/// as UTC would silently shift which calendar day an entry appears to fall
/// on whenever the device's local timezone is ahead of UTC and the wall
/// clock is between midnight UTC and local midnight — exactly the kind of
/// timezone shift PHASE8's Step 12 calls out to avoid.
DateTime parseDateOnly(String yyyyMMdd) {
  final parts = yyyyMMdd.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}
