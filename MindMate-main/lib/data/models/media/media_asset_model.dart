/// Mirrors `app.schemas.media.MediaAssetRead`/`MediaAssetDetail` — the
/// shape returned by every `/media*` endpoint (PHASE14D audit report,
/// Section 2/3; `backend/app/schemas/media.py`). One class covers both:
/// [downloadUrl]/[downloadUrlExpiresInSeconds] are simply `null` when this
/// is parsed from a list item (`GET /media`) or an upload response
/// (`POST /media/upload`), which are `MediaAssetRead`-shaped and carry
/// neither field, and non-null only when parsed from `GET /media/{id}`'s
/// `MediaAssetDetail` response, the one endpoint that returns them.
///
/// PHASE14E deliberately does NOT decode `user_id`, even though the
/// backend's `MediaAssetRead` includes it (unlike, say, [ShoutoutModel]/
/// [JournalModel], which do keep it for completeness) — this phase's own
/// spec calls it out explicitly as a field this model must not carry.
/// Ownership is entirely the backend's concern (derived from the Bearer
/// token on every request — see `get_current_active_user`); nothing on
/// the Flutter side ever needs to read it back.
///
/// Also deliberately absent: `object_key` (never sent by the backend to
/// begin with — see `MediaAssetRead`'s own fields and
/// `test_metadata_is_created_correctly` in `backend/tests/test_media.py`,
/// which asserts exactly that) and `updated_at` — the backend ORM model
/// has one (`TimestampMixin`), but neither `MediaAssetRead` nor
/// `MediaAssetDetail` actually serializes it, so it is not decoded here
/// either (per this phase's own instruction: match the backend's real
/// wire shape, never invent a field that merely sounds plausible).
///
/// No code generation is used, matching every other model under
/// `lib/data/models` (see `journal_model.dart`, `vault_lock_model.dart`).
class MediaAssetModel {
  const MediaAssetModel({
    required this.id,
    required this.mediaType,
    this.originalFilename,
    this.title,
    required this.contentType,
    required this.fileSize,
    this.durationSeconds,
    required this.createdAt,
    this.legacySource,
    this.legacyCreatedAt,
    this.checksumSha256,
    this.downloadUrl,
    this.downloadUrlExpiresInSeconds,
  });

  final String id;

  /// One of `'voice'`, `'image'`, `'video'` — always backend-derived from
  /// the uploaded file's actual content type (PHASE14D audit report,
  /// Section 2); never a value this app asserts on upload.
  final String mediaType;

  /// The originally-uploaded filename, kept purely for display — see the
  /// backend model's own doc for why it is never trusted for anything
  /// else. `null` is a normal, valid state (the backend column itself is
  /// nullable), not a parsing failure.
  final String? originalFilename;

  /// The Vault rename target (PHASE14B). `null` until a caller `PATCH`es
  /// it — not an error state; every freshly-uploaded item starts this way
  /// (see `test_returned_title_is_correct`/`test_null_title_remains_valid_
  /// for_a_never_renamed_item` in `backend/tests/test_media.py`).
  final String? title;

  final String contentType;
  final int fileSize;

  /// Only meaningful for voice (and, in principle, video); `null` for
  /// images and for anything uploaded without it.
  final int? durationSeconds;

  final DateTime createdAt;

  /// PHASE14I-C. Mirrors the backend's `MediaAssetRead.legacy_source`
  /// (PHASE14I-B) — `"<image|voice|video>:<legacy-hive-id>"` when this
  /// item was created by [LegacyMediaMigrationService], `null` for every
  /// ordinary upload (which is every item before this phase, and the
  /// overwhelming majority of items after it). Decoded because the
  /// migration runner's own duplicate-check (`GET /media?legacy_source=
  /// ...`) needs to read it back to confirm which Hive record a returned
  /// asset already corresponds to — not merely because the backend
  /// happens to include it.
  final String? legacySource;

  /// PHASE14I-C. Mirrors the backend's `MediaAssetRead.legacy_created_at`
  /// — the preserved original Hive `DateTime`, when this is a migrated
  /// item; `null` otherwise. Deliberately never used in place of
  /// [createdAt] by anything in this model itself — a future Vault
  /// screen decides which one to display (see the backend's own
  /// `MediaAssetRead` doc for the same guidance: `legacyCreatedAt` is a
  /// migrated note's real date, `createdAt` is migration time).
  final DateTime? legacyCreatedAt;

  /// PHASE14I-G.1/H. Mirrors the backend's `MediaAssetRead.checksum_sha256`
  /// — the lowercase hex SHA-256 digest of the exact bytes this backend
  /// received for this upload, computed once at upload time. `null` for
  /// every row created before PHASE14I-G.1's backend change (no backfill
  /// was performed there) and, in principle, for any future row whose
  /// hash somehow can't be computed, though no such path exists today.
  /// Decoded because [LegacyMediaVerificationService] needs it back to
  /// compare against a freshly-downloaded copy's own locally-computed
  /// hash — see that class's own doc for the full verify-before-delete
  /// contract this exists to support. Never derived from — and never
  /// exposes — the storage `object_key` or any filesystem path.
  final String? checksumSha256;

  /// Non-null only when this was parsed from `GET /media/{id}`'s
  /// `MediaAssetDetail` response — a time-limited URL the client can use
  /// to fetch the object's bytes directly, bypassing this API. Never a
  /// storage path, object key, or anything else that would let a caller
  /// construct one of its own (PHASE14D audit report, Section 3).
  final String? downloadUrl;

  /// Paired with [downloadUrl]: how many seconds from the moment this
  /// response was generated that URL remains valid for (15 minutes on the
  /// backend today — `DOWNLOAD_URL_EXPIRES_IN_SECONDS` in
  /// `app/services/media_service.py`). `null` exactly when [downloadUrl]
  /// is `null`.
  final int? downloadUrlExpiresInSeconds;

  factory MediaAssetModel.fromJson(Map<String, dynamic> json) {
    return MediaAssetModel(
      id: json['id'] as String,
      mediaType: json['media_type'] as String,
      originalFilename: json['original_filename'] as String?,
      title: json['title'] as String?,
      contentType: json['content_type'] as String,
      fileSize: json['file_size'] as int,
      durationSeconds: json['duration_seconds'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      legacySource: json['legacy_source'] as String?,
      legacyCreatedAt: json['legacy_created_at'] != null
          ? DateTime.parse(json['legacy_created_at'] as String)
          : null,
      checksumSha256: json['checksum_sha256'] as String?,
      downloadUrl: json['download_url'] as String?,
      downloadUrlExpiresInSeconds:
          json['download_url_expires_in_seconds'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'media_type': mediaType,
    'original_filename': originalFilename,
    'title': title,
    'content_type': contentType,
    'file_size': fileSize,
    'duration_seconds': durationSeconds,
    'created_at': createdAt.toIso8601String(),
    'legacy_source': legacySource,
    if (legacyCreatedAt != null)
      'legacy_created_at': legacyCreatedAt!.toIso8601String(),
    'checksum_sha256': checksumSha256,
    if (downloadUrl != null) 'download_url': downloadUrl,
    if (downloadUrlExpiresInSeconds != null)
      'download_url_expires_in_seconds': downloadUrlExpiresInSeconds,
  };
}

/// Mirrors `app.schemas.common.Page[MediaAssetRead]` — `GET /media`'s
/// response shape. Not a generic `Page<T>`: no reusable pagination model
/// exists yet anywhere in `lib/` (every existing repository —
/// `JournalRepository.getEntriesForRange`, `ShoutoutRepository.getForDate`,
/// etc. — reads `body?['items']` directly and discards `total`/`limit`/
/// `offset` entirely), so this is the smallest media-specific shape that
/// actually carries all four fields the backend returns, per this phase's
/// own instruction not to hard-code pagination behavior that differs from
/// it.
class MediaAssetPage {
  const MediaAssetPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<MediaAssetModel> items;
  final int total;
  final int limit;
  final int offset;

  factory MediaAssetPage.fromJson(Map<String, dynamic> json) {
    final items = json['items'] as List<dynamic>? ?? const [];
    return MediaAssetPage(
      items: items
          .map((item) => MediaAssetModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      limit: json['limit'] as int,
      offset: json['offset'] as int,
    );
  }
}
