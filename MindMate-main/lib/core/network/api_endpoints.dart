/// Phase 7 added `/auth/*` and `/health`; Phase 8 added `/journals`; Phase 9
/// added `/moods`; Phase 10 added `/checklists`; Phase 11B adds `/scheduler`.
///
/// Still deliberately limited to the features actually wired up so far —
/// every other backend route (shoutouts, media, relationships, stress,
/// reflections) is real and working server-side (see
/// PHASE6_INTEGRATION_AUDIT.md), but wiring them up is explicitly out of
/// scope until the phase that migrates each one. Do not add constants for
/// them here yet; add them in the phase that actually integrates each
/// feature, so this file stays an accurate map of what the Flutter app
/// actually calls.
class ApiEndpoints {
  ApiEndpoints._();

  static const String health = '/health';

  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String refresh = '/auth/refresh';
  static const String logout = '/auth/logout';
  static const String me = '/auth/me';

  /// `GET` (list, with optional `start_date`/`end_date`/`limit`/`offset`
  /// query params) and `POST` (create) both live at this exact path — see
  /// `backend/app/api/routes/journals.py`.
  static const String journals = '/journals';

  /// `GET` (retrieve one), `PATCH` (update), and `DELETE` all address a
  /// single entry by its backend-assigned id — never by date; see PHASE8
  /// audit report, Section J.3, for why the old Firestore date-as-id scheme
  /// doesn't carry over.
  static String journalById(String journalId) => '$journals/$journalId';

  /// `GET` (list, with optional `start_date`/`end_date`/`limit`/`offset`
  /// query params) and `POST` (create) both live at this exact path — see
  /// `backend/app/api/routes/moods.py`.
  static const String moods = '/moods';

  /// `GET` (retrieve one) and `PATCH` (update) address a single entry by its
  /// backend-assigned id — same pattern as [journalById]. There is no
  /// `DELETE /moods/{id}` on the backend (see PHASE9 audit report, Section
  /// E) so, unlike `journalById`, this is never used for a delete call.
  static String moodById(String moodId) => '$moods/$moodId';

  /// The fixed, global task catalog — `GET` only, no `POST`/`DELETE` (the
  /// app has no way to add/remove checklist items; see
  /// `backend/app/api/routes/checklists.py`). Returns a bare JSON array,
  /// not a `Page[T]` object, so this goes through `ApiClient.getList`, not
  /// `ApiClient.get` — see that method's doc.
  static const String checklistItems = '/checklists/items';

  /// `GET` (this user's completion state for every catalog item on this
  /// date) and `PATCH` (toggle one or more items for this date) both
  /// address a whole day by its date, never by a per-completion id — see
  /// PHASE10 audit report, Section 2.
  static String checklistByDate(String entryDate) => '/checklists/$entryDate';

  /// `GET` (this user's scheduled rows for the date) and `PUT` (whole-day
  /// replace) both address a single date, never a per-row id — same shape
  /// as [checklistByDate]. See PHASE11B and `backend/app/api/routes/schedulers.py`.
  static const String scheduler = '/scheduler';
  static String schedulerByDate(String entryDate) => '$scheduler/$entryDate';
}
