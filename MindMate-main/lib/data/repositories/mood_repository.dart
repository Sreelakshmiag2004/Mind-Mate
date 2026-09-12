import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../models/journal/journal_model.dart' show formatDateOnly;
import '../models/mood/mood_model.dart';

/// The only layer in the app that knows how Mood actually talks to the
/// FastAPI backend — `homepage.dart` calls methods on this class, never
/// [ApiClient] directly, matching the pattern `JournalRepository` already
/// established in Phase 8 (see PHASE9 audit report, Section K).
///
/// Deliberately does NOT send `user_id` on any request — the backend
/// derives the acting user from the Bearer token `ApiClient` attaches (see
/// `get_current_active_user` in `backend/app/dependencies/auth.py`).
///
/// Has no `delete()` method: the backend exposes no `DELETE /moods/{id}` —
/// the existing app has no delete flow for moods (only add/edit via the
/// calendar) — see PHASE9 audit report, Section E.
class MoodRepository {
  MoodRepository({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// Lazily-constructed app-wide singleton, matching
  /// `JournalRepository.instance`/`AuthRepository.instance` (see those
  /// classes' docs for why: no DI package in this project, and a second
  /// instance would just be a second, uncoordinated `ApiClient`). Tests
  /// should construct `MoodRepository(apiClient: ...)` directly.
  static MoodRepository get instance => _instance ??= MoodRepository();
  static MoodRepository? _instance;

  final ApiClient _apiClient;

  /// `GET /moods?start_date=<date>&end_date=<date>&limit=1&offset=0` — the
  /// exact-date lookup the backend doesn't offer as its own endpoint, done
  /// as a one-day inclusive range instead (same approach as
  /// `JournalRepository.getForDate`). Returns the matching entry, or `null`
  /// if that date has none.
  Future<MoodModel?> getForDate(DateTime date) async {
    final entries = await getEntriesForRange(startDate: date, endDate: date, limit: 1, offset: 0);
    return entries.isEmpty ? null : entries.first;
  }

  /// `GET /moods` filtered to the inclusive `[startDate, endDate]` range,
  /// newest first (the backend's own ordering — see
  /// `mood_repository.list_for_user` server-side).
  ///
  /// PHASE9's Home calendar calls this with exactly the currently visible
  /// grid range (a half-month) rather than fetching the user's entire mood
  /// history — see `homepage.dart`'s `_loadMoodsForVisibleRange` — so
  /// `limit`/`offset` only matter if a single half-month somehow exceeds
  /// the backend's page size, which a calendar grid of at most ~16 days
  /// never can.
  Future<List<MoodModel>> getEntriesForRange({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 100,
    int offset = 0,
  }) async {
    final body = await _apiClient.get(
      ApiEndpoints.moods,
      queryParameters: {
        'start_date': formatDateOnly(startDate),
        'end_date': formatDateOnly(endDate),
        'limit': limit,
        'offset': offset,
      },
    );
    final items = body?['items'] as List<dynamic>? ?? const [];
    return items.map((item) => MoodModel.fromJson(item as Map<String, dynamic>)).toList();
  }

  /// `GET /moods/{moodId}`. Not called by the current Home calendar (which
  /// only ever needs a date-scoped range or an upsert), but included for
  /// repository completeness, mirroring `JournalRepository`.
  Future<MoodModel> getById(String moodId) async {
    final body = await _apiClient.get(ApiEndpoints.moodById(moodId));
    return MoodModel.fromJson(body!);
  }

  /// `POST /moods`. Throws [ConflictException] (409) if [entryDate] already
  /// has an entry for this user — callers that don't already know whether
  /// that date has an entry should use [createOrUpdate] instead, which
  /// handles that case.
  Future<MoodModel> create({required DateTime entryDate, required int moodValue}) async {
    final body = await _apiClient.post(
      ApiEndpoints.moods,
      data: {'entry_date': formatDateOnly(entryDate), 'mood_value': moodValue},
    );
    return MoodModel.fromJson(body!);
  }

  /// `PATCH /moods/{moodId}`. Only the fields passed are sent, so an
  /// omitted [moodValue]/[entryDate] leaves that field unchanged
  /// server-side (PATCH semantics — see `MoodUpdate` in
  /// `backend/app/schemas/mood.py`).
  Future<MoodModel> update({required String id, DateTime? entryDate, int? moodValue}) async {
    final body = await _apiClient.patch(
      ApiEndpoints.moodById(id),
      data: {
        if (entryDate != null) 'entry_date': formatDateOnly(entryDate),
        if (moodValue != null) 'mood_value': moodValue,
      },
    );
    return MoodModel.fromJson(body!);
  }

  /// Upserts the mood value for [entryDate], per PHASE9's Step 6 save flow:
  ///
  /// 1. Try [create].
  /// 2. If it succeeds, return the created [MoodModel].
  /// 3. If the backend responds with a 409 (an entry for [entryDate]
  ///    already exists — e.g. the calendar's local cache of which dates
  ///    have entries is stale, or another device saved one since this
  ///    screen last loaded), look the real entry up via [getForDate] and
  ///    [update] it instead of blindly retrying `POST`, which would just
  ///    409 again.
  /// 4. Any other [ApiException] (network, 422, 401-after-failed-refresh,
  ///    ...) propagates unchanged to the caller.
  Future<MoodModel> createOrUpdate({required DateTime entryDate, required int moodValue}) async {
    try {
      return await create(entryDate: entryDate, moodValue: moodValue);
    } on ConflictException {
      final existing = await getForDate(entryDate);
      if (existing == null) rethrow;
      return update(id: existing.id, moodValue: moodValue);
    }
  }
}
