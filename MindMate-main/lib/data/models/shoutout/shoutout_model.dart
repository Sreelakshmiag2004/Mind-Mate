import '../journal/journal_model.dart' show formatDateOnly, parseDateOnly;

/// Mirrors `app.schemas.shoutout.ShoutoutRead` — the shape returned by
/// every `/shoutouts` endpoint, including `POST .../feel-better` (see
/// PHASE13 backend contract verification report, Section 1/2).
///
/// [userId] is decoded purely because the backend includes it in every
/// response — it is never used client-side to decide ownership or to
/// address a request; the backend alone derives "whose shoutout is this"
/// from the Bearer token (PHASE13: "never send user_id").
///
/// No code generation is used, matching every other model under
/// `lib/data/models` (see `journal_model.dart`, `mood_model.dart`).
class ShoutoutModel {
  const ShoutoutModel({
    required this.id,
    required this.userId,
    required this.entryDate,
    this.title,
    this.content,
    this.feltBetter,
    this.feltBetterAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Decoded for completeness only — see the class doc. Never read by any
  /// repository/UI code to make an ownership or addressing decision.
  final String userId;

  /// Date-only — the calendar day this shoutout belongs to, with no
  /// time-of-day and no timezone attached. Parsed from the backend's
  /// `"YYYY-MM-DD"` string with [parseDateOnly] rather than `DateTime.parse`
  /// directly — see that function's doc for why.
  final DateTime entryDate;
  final String? title;
  final String? content;

  /// `null` until the one-shot "did you feel better?" follow-up has been
  /// answered; `true`/`false` afterward, and fixed forever once set — the
  /// backend rejects a second answer with a 409 (PHASE13 Section 5).
  final bool? feltBetter;

  /// Set together with [feltBetter], the moment it was first answered.
  /// Always `null` while [feltBetter] is `null`.
  final DateTime? feltBetterAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ShoutoutModel.fromJson(Map<String, dynamic> json) {
    return ShoutoutModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      entryDate: parseDateOnly(json['entry_date'] as String),
      title: json['title'] as String?,
      content: json['content'] as String?,
      feltBetter: json['felt_better'] as bool?,
      feltBetterAt: json['felt_better_at'] == null ? null : DateTime.parse(json['felt_better_at'] as String),
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
    'felt_better': feltBetter,
    'felt_better_at': feltBetterAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}
