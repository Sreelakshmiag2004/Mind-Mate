/// Phase 7 added `/auth/*` and `/health`; Phase 8 added `/journals`; Phase 9
/// adds `/moods`.
///
/// Still deliberately limited to the features actually wired up so far —
/// every other backend route (checklists, shoutouts, media, relationships,
/// stress, reflections) is real and working server-side (see
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
}
