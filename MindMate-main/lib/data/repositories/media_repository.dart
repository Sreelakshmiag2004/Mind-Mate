import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../models/media/media_asset_model.dart';

/// The only layer in the app that knows how Vault media actually talks to
/// the FastAPI backend (PHASE14E) — matching the pattern `JournalRepository`/
/// `ShoutoutRepository`/`VaultLockRepository` already established. No Vault
/// screen (`vault.dart`, `viewall_images.dart`, `viewall_videos.dart`,
/// `AllVoiceNotesPage`) calls this yet — none of them are wired up in this
/// phase; that is deliberately deferred to the image/video/voice migration
/// phases that follow (PHASE14D audit report, Section 13). This repository
/// exists on its own, fully unit-testable, ahead of any caller.
///
/// Deliberately does NOT send `user_id`, a Firebase UID, a username, a
/// `media_type`, or an `object_key` on any request — the backend derives
/// the acting user from the Bearer token [ApiClient] attaches, derives
/// `media_type` itself from the uploaded file's actual content type, and
/// never accepts or exposes `object_key` at all (PHASE14D audit report,
/// Section 2/3). Nothing here ever reads or stores a local file path as a
/// backend identifier, either — every method below works purely in bytes,
/// ids, and [MediaAssetModel]/[MediaAssetPage].
class MediaRepository {
  MediaRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  /// Lazily-constructed app-wide singleton, matching
  /// `VaultLockRepository.instance`/`ShoutoutRepository.instance`. Tests
  /// should construct `MediaRepository(apiClient: ...)` directly.
  static MediaRepository get instance => _instance ??= MediaRepository();
  static MediaRepository? _instance;

  final ApiClient _apiClient;

  /// `POST /media/upload` — a direct multipart upload of [fileBytes].
  /// [durationSeconds] is only meaningful for voice (and, in principle,
  /// video) and is sent as an optional form field, exactly like the
  /// backend's `Form(default=None, ge=0)` expects; omitted entirely when
  /// `null`, matching the backend's own "client-reported, display-only"
  /// treatment of it (PHASE14D audit report, Section 2).
  ///
  /// [legacySource]/[legacyCreatedAt] (PHASE14I-C) are the two fields
  /// [LegacyMediaMigrationService] sends for a legacy Hive migration
  /// upload — see `backend/app/schemas/media.py`'s `MediaUploadLegacyFields`
  /// for the exact contract. Both omitted entirely when `null`, exactly
  /// like [durationSeconds] above, so a normal (non-legacy) upload's
  /// request body is byte-for-byte unchanged from before this phase.
  /// [legacyCreatedAt] is sent as `.toUtc().toIso8601String()` — never the
  /// raw (possibly local-time) value — because the backend cannot safely
  /// reinterpret a naive datetime string itself (PHASE14I-B implementation
  /// report, "Timezone/date handling"); converting here, once, is what
  /// lets every caller (today, only [LegacyMediaMigrationService]) hand
  /// this a plain Hive `DateTime` without repeating that conversion.
  ///
  /// An unsupported [contentType] surfaces as the backend's 415 (mapped by
  /// [ApiClient]/[ApiException] to [UnknownApiException], same as any
  /// other unmapped status), an oversized [fileBytes] as its 413, a blank/
  /// malformed [legacySource] or invalid [legacyCreatedAt] as its 422 (via
  /// [ValidationException]) — this repository invents no second exception
  /// system, per this phase's own instruction; every failure goes through
  /// the existing [ApiException] hierarchy exactly like every other
  /// repository in the app.
  Future<MediaAssetModel> upload({
    required List<int> fileBytes,
    required String filename,
    required String contentType,
    int? durationSeconds,
    String? legacySource,
    DateTime? legacyCreatedAt,
  }) async {
    final body = await _apiClient.uploadMultipart(
      ApiEndpoints.mediaUpload,
      fileBytes: fileBytes,
      filename: filename,
      contentType: contentType,
      fields: {
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
        if (legacySource != null) 'legacy_source': legacySource,
        if (legacyCreatedAt != null)
          'legacy_created_at': legacyCreatedAt.toUtc().toIso8601String(),
      },
    );
    return MediaAssetModel.fromJson(body!);
  }

  /// `GET /media` — this user's own media only (never another user's; see
  /// the backend's own ownership enforcement, PHASE14D audit report,
  /// Section 2). [mediaType], when given, must be one of `'voice'`,
  /// `'image'`, `'video'` — matching the backend's own
  /// `pattern="^(voice|image|video)$"` validation on this query parameter;
  /// this repository does not re-validate it client-side, so an invalid
  /// value surfaces as the backend's own 422 via [ApiException], not a
  /// silent local rejection.
  ///
  /// [legacySource] (PHASE14I-C), when given, is the exact-match
  /// `legacy_source` lookup filter [LegacyMediaMigrationService] uses to
  /// ask "has this Hive record already been migrated?" without any local
  /// migration-status store of its own — see `backend/app/api/routes/
  /// media.py`'s `GET /media?legacy_source=...`. Omitted entirely when
  /// `null`, exactly like [mediaType], so a normal listing call is
  /// unaffected.
  Future<MediaAssetPage> list({
    String? mediaType,
    String? legacySource,
    int limit = 30,
    int offset = 0,
  }) async {
    final body = await _apiClient.get(
      ApiEndpoints.media,
      queryParameters: {
        if (mediaType != null) 'media_type': mediaType,
        if (legacySource != null) 'legacy_source': legacySource,
        'limit': limit,
        'offset': offset,
      },
    );
    return MediaAssetPage.fromJson(body!);
  }

  /// `GET /media/{mediaId}` — the one call that returns a fresh
  /// [MediaAssetModel.downloadUrl]; a future Vault screen resolves this
  /// just before actually displaying/playing an item, never caches it
  /// long-term (PHASE14D audit report, Section 3/4 — the URL is
  /// time-limited). Throws [NotFoundException] (404) if [mediaId] doesn't
  /// exist or isn't this user's.
  Future<MediaAssetModel> get(String mediaId) async {
    final body = await _apiClient.get(ApiEndpoints.mediaById(mediaId));
    return MediaAssetModel.fromJson(body!);
  }

  /// `PATCH /media/{mediaId}` — renames ONLY the display [title]; the body
  /// is exactly `{"title": ...}`, nothing else (the backend's
  /// `MediaAssetUpdate` accepts no other field — see
  /// `app/schemas/media.py`). Throws [ValidationException] (422) for a
  /// blank/whitespace-only or over-200-character [title], and
  /// [NotFoundException] (404) if [mediaId] doesn't exist or isn't this
  /// user's.
  Future<MediaAssetModel> rename({
    required String mediaId,
    required String title,
  }) async {
    final body = await _apiClient.patch(
      ApiEndpoints.mediaById(mediaId),
      data: {'title': title},
    );
    return MediaAssetModel.fromJson(body!);
  }

  /// `DELETE /media/{mediaId}` — `204` on success. This repository only
  /// reports success/failure; it never touches Hive or any UI state
  /// itself — per this phase's own instruction, a future caller must never
  /// optimistically delete a local record before this completes.
  ///
  /// Deliberately `async`/`await` rather than a bare expression-bodied
  /// `=> _apiClient.delete(...)` (unlike, say, `JournalRepository.delete`)
  /// — every other method in this class already awaits its [_apiClient]
  /// call, and doing the same here means a failure is always reported as
  /// a rejected [Future], never a synchronous throw, regardless of how the
  /// underlying call fails.
  Future<void> delete(String mediaId) async {
    await _apiClient.delete(ApiEndpoints.mediaById(mediaId));
  }

  /// PHASE14I-H: downloads the raw bytes at an arbitrary absolute [url] —
  /// used only for a presigned download URL obtained from [get]'s
  /// [MediaAssetModel.downloadUrl], by [LegacyMediaVerificationService].
  /// A thin passthrough to [ApiClient.downloadBytes] (see that method's
  /// own doc for why it never attaches this app's Bearer JWT to the
  /// request) — kept here, rather than the verification service calling
  /// [ApiClient] directly, so [MediaRepository] stays the one layer that
  /// knows how Vault media talks to the backend, matching every other
  /// method in this class.
  Future<List<int>> downloadBytes(String url) => _apiClient.downloadBytes(url);
}
