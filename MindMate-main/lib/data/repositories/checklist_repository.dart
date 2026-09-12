import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../models/checklist/checklist_model.dart';
import '../models/journal/journal_model.dart' show formatDateOnly;

/// The only layer in the app that knows how Checklist actually talks to the
/// FastAPI backend — `homepage.dart` calls methods on this class, never
/// [ApiClient] directly, matching the pattern `JournalRepository`/
/// `MoodRepository` already established in Phases 8/9 (see PHASE10 audit
/// report, Section 8).
///
/// Deliberately does NOT send `user_id` on any request — the backend
/// derives the acting user from the Bearer token `ApiClient` attaches (see
/// `get_current_active_user` in `backend/app/dependencies/auth.py`).
///
/// Unlike Journal/Mood, there is no per-entry id-based `create`/`update`
/// here: Checklist has no creatable/deletable "entry" at all, only 5 fixed
/// catalog items whose per-date completion is toggled — see
/// `backend/app/api/routes/checklists.py`'s own module docstring.
class ChecklistRepository {
  ChecklistRepository({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// Lazily-constructed app-wide singleton, matching
  /// `JournalRepository.instance`/`MoodRepository.instance`. Tests should
  /// construct `ChecklistRepository(apiClient: ...)` directly.
  static ChecklistRepository get instance => _instance ??= ChecklistRepository();
  static ChecklistRepository? _instance;

  final ApiClient _apiClient;

  /// `GET /checklists/items` — the fixed, global task catalog. Returns a
  /// bare JSON array server-side (`list[ChecklistItemRead]`), so this goes
  /// through [ApiClient.getList], not [ApiClient.get] — see that method's
  /// doc for why a separate call was needed.
  Future<List<ChecklistItem>> getCatalog() async {
    final items = await _apiClient.getList(ApiEndpoints.checklistItems);
    return (items ?? const []).map((item) => ChecklistItem.fromJson(item as Map<String, dynamic>)).toList();
  }

  /// `GET /checklists/{entry_date}` — this user's completion state for
  /// every catalog item on [date]. Always returns all catalog items, each
  /// defaulting to `completed: false` if never toggled on that date (the
  /// backend assembles this server-side; nothing here needs to reconcile
  /// "catalog minus completions" itself).
  Future<ChecklistDay> getDay(DateTime date) async {
    final body = await _apiClient.get(ApiEndpoints.checklistByDate(formatDateOnly(date)));
    return ChecklistDay.fromJson(body!);
  }

  /// `PATCH /checklists/{entry_date}` — toggles every `(itemId, completed)`
  /// pair in [completions] for [date] in one request, returning the full
  /// day's state afterward. [completions] is keyed by item id so a given
  /// item can only appear once per call (matching the one-row-per-item
  /// reality of `checklist_completions`).
  Future<ChecklistDay> updateDay(DateTime date, Map<String, bool> completions) async {
    final body = await _apiClient.patch(
      ApiEndpoints.checklistByDate(formatDateOnly(date)),
      data: {
        'completions': completions.entries.map((entry) => {'item_id': entry.key, 'completed': entry.value}).toList(),
      },
    );
    return ChecklistDay.fromJson(body!);
  }

  /// Convenience wrapper around [updateDay] for the single-item toggle
  /// every real call site actually needs (one checkbox tapped at a time) —
  /// sends exactly `{"completions": [{"item_id": itemId, "completed":
  /// completed}]}`, per PHASE10 Step 3.
  Future<ChecklistDay> toggleItem(DateTime date, String itemId, bool completed) {
    return updateDay(date, {itemId: completed});
  }
}
