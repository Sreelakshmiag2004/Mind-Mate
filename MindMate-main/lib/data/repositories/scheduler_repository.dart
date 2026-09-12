import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../models/journal/journal_model.dart' show formatDateOnly;
import '../models/scheduler/scheduler_model.dart';

/// The only layer in the app that knows how Scheduler actually talks to the
/// FastAPI backend — `homepage.dart`/`scheduler_details_page.dart` call
/// methods on this class, never [ApiClient] directly, matching the pattern
/// `ChecklistRepository`/`MoodRepository`/`JournalRepository` already
/// established (PHASE11B).
///
/// Deliberately does NOT send `user_id` on any request — the backend
/// derives the acting user from the Bearer token `ApiClient` attaches (see
/// `get_current_active_user` in `backend/app/dependencies/auth.py`).
///
/// There is no "yesterday fallback" here: per PHASE11A product decision 1,
/// that stays entirely client-side (see `homepage.dart`'s `loadScheduler`)
/// — this repository only ever answers "what's scheduled on this exact
/// date," same as the backend itself.
class SchedulerRepository {
  SchedulerRepository({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// Lazily-constructed app-wide singleton, matching
  /// `ChecklistRepository.instance`/`MoodRepository.instance`. Tests should
  /// construct `SchedulerRepository(apiClient: ...)` directly.
  static SchedulerRepository get instance => _instance ??= SchedulerRepository();
  static SchedulerRepository? _instance;

  final ApiClient _apiClient;

  /// `GET /scheduler/{entry_date}` — this user's scheduled rows for [date],
  /// ordered by time. An empty `items` list means nothing is scheduled; it
  /// is never an error (mirrors the backend route's own contract).
  Future<SchedulerDay> getDay(DateTime date) async {
    final body = await _apiClient.get(ApiEndpoints.schedulerByDate(formatDateOnly(date)));
    return SchedulerDay.fromJson(body!);
  }

  /// `PUT /scheduler/{entry_date}` — replaces this user's ENTIRE schedule
  /// for [date] with [rows] in one call: a row from the previous save that
  /// isn't included here is deleted; an empty [rows] clears the day (see
  /// `SchedulerDayUpdate`'s docstring on the backend). Returns the full
  /// saved day, parsed from the response, so the caller updates its UI only
  /// from what the backend actually persisted — never from what was sent.
  ///
  /// Two rows with the same `scheduledTime` are rejected by the backend
  /// with a 422 (`ValidationException`) before anything is written — see
  /// that schema's own duplicate-time validation. Callers (specifically
  /// `scheduler_details_page.dart`) are expected to check for duplicate
  /// times themselves before calling this, so a user sees a clear,
  /// friendly message instead of a raw validation error.
  Future<SchedulerDay> replaceDay(DateTime date, List<SchedulerRowInput> rows) async {
    final body = await _apiClient.put(
      ApiEndpoints.schedulerByDate(formatDateOnly(date)),
      data: {'rows': rows.map((row) => row.toJson()).toList()},
    );
    return SchedulerDay.fromJson(body!);
  }
}
