import '../journal/journal_model.dart' show formatDateOnly, parseDateOnly;

/// Mirrors `app.schemas.mood.MoodRead` — the shape returned by every
/// `/moods` endpoint (see PHASE9 audit report, Section E). Structurally
/// identical to `JournalModel` apart from the single `mood_value` field
/// replacing `title`/`content` — Mood has no equivalent of Journal's
/// `description` <-> `content` rename; `mood_value` is the same name on
/// both sides.
///
/// Deliberately reuses [formatDateOnly]/[parseDateOnly] from
/// `journal_model.dart` rather than redefining them — they're
/// resource-agnostic date-only helpers, not Journal-specific, and PHASE9's
/// instructions call out avoiding a duplicate copy.
///
/// No code generation is used, matching every other model under
/// `lib/data/models` (see `journal_model.dart`, `token_response_model.dart`).
class MoodModel {
  const MoodModel({
    required this.id,
    required this.userId,
    required this.entryDate,
    required this.moodValue,
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

  /// 0-100, matching the app's existing percent scale (`app.schemas.mood.MoodCreate`).
  final int moodValue;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory MoodModel.fromJson(Map<String, dynamic> json) {
    return MoodModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      entryDate: parseDateOnly(json['entry_date'] as String),
      moodValue: json['mood_value'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'entry_date': formatDateOnly(entryDate),
    'mood_value': moodValue,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}
