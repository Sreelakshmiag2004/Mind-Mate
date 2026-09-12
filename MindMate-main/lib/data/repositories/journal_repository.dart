import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../models/journal/journal_model.dart';

/// The only layer in the app that knows how Journal actually talks to the
/// FastAPI backend — `journal_page.dart` calls methods on this class, never
/// [ApiClient] directly (see PHASE8 audit report, Section L), matching the
/// pattern `AuthRepository` already established in Phase 7.
///
/// Every method here works purely in terms of `JournalModel`/`DateTime`;
/// the `description` (Flutter UI) <-> `content` (backend) field rename
/// happens exactly once, at the call sites below, so nothing above this
/// repository ever needs to know the backend calls it `content`.
///
/// Deliberately does NOT send `user_id` on any request — the backend
/// derives the acting user from the Bearer token `ApiClient` attaches (see
/// `get_current_active_user` in `backend/app/dependencies/auth.py`).
class JournalRepository {
  JournalRepository({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// Lazily-constructed app-wide singleton, matching `AuthRepository.instance`
  /// (see that class's doc for why: no DI package in this project, and a
  /// second instance would just be a second, uncoordinated `ApiClient`).
  /// Tests should construct `JournalRepository(apiClient: ...)` directly.
  static JournalRepository get instance => _instance ??= JournalRepository();
  static JournalRepository? _instance;

  final ApiClient _apiClient;

  /// `GET /journals?start_date=<date>&end_date=<date>&limit=1&offset=0` —
  /// per PHASE8 Step 3, the exact-date lookup the backend doesn't offer as
  /// its own endpoint, done as a one-day inclusive range instead. Returns
  /// the matching entry, or `null` if that date has none.
  Future<JournalModel?> getForDate(DateTime date) async {
    final entries = await getEntriesForRange(date, date, limit: 1, offset: 0);
    return entries.isEmpty ? null : entries.first;
  }

  /// `GET /journals` filtered to the inclusive `[startDate, endDate]` range,
  /// newest first (the backend's own ordering — see
  /// `journal_repository.list_for_user` server-side). Used both for
  /// [getForDate] (a one-day range) and for streak calculation
  /// (`journal_streak.dart`), which needs one list request covering enough
  /// history rather than one request per day.
  Future<List<JournalModel>> getEntriesForRange(
    DateTime startDate,
    DateTime endDate, {
    int limit = 30,
    int offset = 0,
  }) async {
    final body = await _apiClient.get(
      ApiEndpoints.journals,
      queryParameters: {
        'start_date': formatDateOnly(startDate),
        'end_date': formatDateOnly(endDate),
        'limit': limit,
        'offset': offset,
      },
    );
    final items = body?['items'] as List<dynamic>? ?? const [];
    return items.map((item) => JournalModel.fromJson(item as Map<String, dynamic>)).toList();
  }

  /// `POST /journals`. Throws [ConflictException] (409) if [entryDate]
  /// already has an entry for this user — callers that don't already know
  /// whether today has an entry should use [createOrUpdate] instead, which
  /// handles that case per PHASE8 Step 4.
  Future<JournalModel> create({required DateTime entryDate, String? title, String? content}) async {
    final body = await _apiClient.post(
      ApiEndpoints.journals,
      data: {
        'entry_date': formatDateOnly(entryDate),
        if (title != null) 'title': title,
        if (content != null) 'content': content,
      },
    );
    return JournalModel.fromJson(body!);
  }

  /// `PATCH /journals/{journalId}`. Only the fields passed are sent, so an
  /// omitted [title]/[content]/[entryDate] leaves that field unchanged
  /// server-side (PATCH semantics — see `JournalUpdate` in
  /// `backend/app/schemas/journal.py`).
  Future<JournalModel> update({
    required String journalId,
    DateTime? entryDate,
    String? title,
    String? content,
  }) async {
    final body = await _apiClient.patch(
      ApiEndpoints.journalById(journalId),
      data: {
        if (entryDate != null) 'entry_date': formatDateOnly(entryDate),
        if (title != null) 'title': title,
        if (content != null) 'content': content,
      },
    );
    return JournalModel.fromJson(body!);
  }

  /// `DELETE /journals/{journalId}`. Not called anywhere in the current UI
  /// (there is no delete affordance in `journal_page.dart` — see PHASE8
  /// audit report, Section F) but included for repository completeness per
  /// PHASE8 Step 3, since the backend already supports it.
  Future<void> delete(String journalId) => _apiClient.delete(ApiEndpoints.journalById(journalId));

  /// Implements PHASE8 Step 4's save flow for "the entry for one date,
  /// which may or may not already exist":
  ///
  /// - [existingId] known (the screen already loaded today's entry) ->
  ///   [update] by that id.
  /// - [existingId] null -> [create]. If the backend unexpectedly responds
  ///   with a 409 (an entry for [entryDate] already exists — e.g. it was
  ///   created by another device/tab since this screen last loaded), this
  ///   looks the real entry up via [getForDate] and [update]s it instead of
  ///   blindly retrying the `POST`, which would just 409 again.
  Future<JournalModel> createOrUpdate({
    required DateTime entryDate,
    String? existingId,
    String? title,
    String? content,
  }) async {
    if (existingId != null) {
      return update(journalId: existingId, entryDate: entryDate, title: title, content: content);
    }
    try {
      return await create(entryDate: entryDate, title: title, content: content);
    } on ConflictException {
      final existing = await getForDate(entryDate);
      if (existing == null) rethrow;
      return update(journalId: existing.id, title: title, content: content);
    }
  }
}
