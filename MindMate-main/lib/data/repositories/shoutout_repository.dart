import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../models/journal/journal_model.dart' show formatDateOnly;
import '../models/shoutout/shoutout_model.dart';

/// The only layer in the app that knows how Shoutout actually talks to the
/// FastAPI backend — `shoutout_page.dart`/`journal_page.dart` call methods
/// on this class, never [ApiClient] directly, matching the pattern
/// `JournalRepository`/`MoodRepository`/`ChecklistRepository`/
/// `SchedulerRepository` already established (PHASE13).
///
/// Deliberately does NOT send `user_id` on any request — the backend
/// derives the acting user from the Bearer token `ApiClient` attaches (see
/// `get_current_active_user` in `backend/app/dependencies/auth.py`), and
/// `ShoutoutCreate` doesn't even accept the field (PHASE13 backend
/// contract verification report, Section 1).
class ShoutoutRepository {
  ShoutoutRepository({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// Lazily-constructed app-wide singleton, matching
  /// `JournalRepository.instance`/`MoodRepository.instance`. Tests should
  /// construct `ShoutoutRepository(apiClient: ...)` directly.
  static ShoutoutRepository get instance => _instance ??= ShoutoutRepository();
  static ShoutoutRepository? _instance;

  final ApiClient _apiClient;

  /// There is deliberately NO `GET /shoutouts/{date}` on the backend
  /// (unlike Checklist/Scheduler) — a date lookup is a one-day inclusive
  /// range list request instead, same approach as
  /// `MoodRepository.getForDate`/`JournalRepository.getForDate` (PHASE13
  /// backend contract verification report, Section 6). Returns the
  /// matching entry, or `null` if that date has none — never an error.
  Future<ShoutoutModel?> getForDate(DateTime date) async {
    final dateStr = formatDateOnly(date);
    final body = await _apiClient.get(
      ApiEndpoints.shoutouts,
      queryParameters: {'start_date': dateStr, 'end_date': dateStr, 'limit': 1, 'offset': 0},
    );
    final items = body?['items'] as List<dynamic>? ?? const [];
    if (items.isEmpty) return null;
    return ShoutoutModel.fromJson(items.first as Map<String, dynamic>);
  }

  /// `GET /shoutouts/{shoutoutId}`. Not called by the current Journal/
  /// Shoutout screens (which always address a shoutout by date via
  /// [getForDate], or already hold its id from a prior load/save), but
  /// included for repository completeness, mirroring
  /// `MoodRepository.getById`/`JournalRepository`.
  Future<ShoutoutModel> getById(String shoutoutId) async {
    final body = await _apiClient.get(ApiEndpoints.shoutoutById(shoutoutId));
    return ShoutoutModel.fromJson(body!);
  }

  /// `POST /shoutouts`. Throws [ConflictException] (409) if [entryDate]
  /// already has a shoutout for this user — callers that don't already
  /// know whether that date has one should use [createOrUpdate] instead.
  Future<ShoutoutModel> create({required DateTime entryDate, String? title, String? content}) async {
    final body = await _apiClient.post(
      ApiEndpoints.shoutouts,
      data: {'entry_date': formatDateOnly(entryDate), 'title': title, 'content': content},
    );
    return ShoutoutModel.fromJson(body!);
  }

  /// `PATCH /shoutouts/{shoutoutId}`. Only the fields passed are sent, so
  /// an omitted [title]/[content] leaves that field unchanged server-side
  /// (PATCH semantics — see `ShoutoutUpdate` in
  /// `backend/app/schemas/shoutout.py`). Never touches `felt_better` —
  /// that is exclusively [answerFeelBetter]'s job (PHASE13 backend
  /// contract verification report, Section 4).
  Future<ShoutoutModel> update({required String id, String? title, String? content}) async {
    final body = await _apiClient.patch(
      ApiEndpoints.shoutoutById(id),
      data: {
        if (title != null) 'title': title,
        if (content != null) 'content': content,
      },
    );
    return ShoutoutModel.fromJson(body!);
  }

  /// Creates-or-updates the shoutout for [entryDate], per PHASE13's
  /// required save flow — deliberately GET-first, NOT a blind POST relying
  /// on a 409 to detect an existing entry (unlike
  /// `MoodRepository.createOrUpdate`'s try-POST-then-fall-back pattern):
  ///
  /// A. [getForDate] to look for an existing entry.
  /// B. If none exists, [create] (POST).
  /// C. If one exists, [update] (PATCH) it, by the id just looked up.
  ///
  /// Returns the saved [ShoutoutModel], whose `id` callers must retain —
  /// both [update] and [answerFeelBetter] address a shoutout by id, never
  /// by date.
  Future<ShoutoutModel> createOrUpdate({required DateTime entryDate, String? title, String? content}) async {
    final existing = await getForDate(entryDate);
    if (existing == null) {
      return create(entryDate: entryDate, title: title, content: content);
    }
    return update(id: existing.id, title: title, content: content);
  }

  /// `POST /shoutouts/{shoutoutId}/feel-better` — answers the one-shot
  /// "did you feel better?" follow-up. Strictly one-shot server-side: a
  /// second call for the same [shoutoutId] throws [ConflictException]
  /// (409), regardless of the [feltBetter] value sent — see PHASE13
  /// backend contract verification report, Section 5. Callers
  /// (`journal_page.dart`'s `_setYesterdayFeelBetter`) are expected to
  /// treat that 409 as "already answered" and re-fetch rather than show a
  /// generic error.
  Future<ShoutoutModel> answerFeelBetter(String shoutoutId, bool feltBetter) async {
    final body = await _apiClient.post(
      ApiEndpoints.shoutoutFeelBetter(shoutoutId),
      data: {'felt_better': feltBetter},
    );
    return ShoutoutModel.fromJson(body!);
  }
}
