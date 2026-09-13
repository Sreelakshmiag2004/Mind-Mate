import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;

import '../models/media/media_asset_model.dart';
import '../repositories/media_repository.dart';
import 'legacy_media_migration_service.dart' show LegacyMediaKind;

export 'legacy_media_migration_service.dart' show LegacyMediaKind;

/// PHASE14I-H — the read-only verify-before-delete foundation for a
/// legacy Hive media item, per the PHASE14I-G audit report's
/// "Verify-before-delete design" section.
///
/// ### What this class is NOT
///
/// * **Not a cleanup tool.** This class never deletes a Hive record,
///   never deletes a local file, never modifies Hive metadata, and never
///   touches `schedulerBox` or Firebase in any way. It answers exactly
///   one question — "does the backend durably and correctly have this
///   item, byte-for-byte?" — and returns a [LegacyMediaVerificationResult]
///   describing the answer. Deciding what to do with a `verified` result
///   (offering a delete action, requiring user confirmation, etc.) is
///   explicitly a future phase's job, not this one's.
/// * **Not a migration tool.** [LegacyMediaMigrationService] is untouched
///   by this phase and this class never calls it, extends it, or shares
///   any mutable state with it — it only reuses its already-public
///   [LegacyMediaKind] enum so there is exactly one source of truth for
///   the three `legacy_source` prefixes.
/// * **Not a bulk/background verifier.** [verify] checks exactly one item
///   per call, on demand; nothing in this class schedules itself,
///   iterates Hive boxes on its own, or runs without being explicitly
///   invoked by a caller (see the class doc's "Integration" note below
///   for the deliberate choice not to wire this into any UI in this
///   phase).
///
/// ### The verification algorithm
///
/// Every check below runs in order; the first one that fails returns
/// immediately with that check's own [LegacyMediaVerificationOutcome] —
/// later checks are never attempted, and nothing partially-passed is
/// ever reported as `verified`:
///
///  1. `GET /media?legacy_source=<kind>:<hiveId>` resolves a backend row
///     at all ([LegacyMediaVerificationOutcome.backendAssetNotFound] if
///     not, including on any network/HTTP failure — a failed lookup is
///     never distinguished from "genuinely doesn't exist" here, matching
///     the fail-closed contract this whole class follows).
///  2. That row's `id` is non-empty
///     ([LegacyMediaVerificationOutcome.invalidBackendId]).
///  3. That row's `legacySource` is an EXACT match for the expected
///     `"<kind>:<hiveId>"` string — never a title, filename, date, or
///     backend-id comparison
///     ([LegacyMediaVerificationOutcome.legacySourceMismatch]).
///  4. Ownership: not a separate check performed here at all — `GET
///     /media?legacy_source=...` is already JWT-scoped server-side (see
///     `backend/app/repositories/media_repository.py`'s
///     `get_by_user_and_legacy_source`/`list_for_user`), so a row this
///     method can even see already belongs to the authenticated caller by
///     construction. There is no way for a Flutter client to
///     independently re-derive backend ownership beyond that.
///  5. `mediaType` equals [kind]'s own prefix
///     ([LegacyMediaVerificationOutcome.mediaTypeMismatch]).
///  6. `legacyCreatedAt` is present
///     ([LegacyMediaVerificationOutcome.missingLegacyCreatedAt]).
///  7. The LOCAL file's byte length (a filesystem `stat`, via
///     [File.length] — the file's CONTENT is never read by this class;
///     see "Memory/file-size safety" below) equals the backend's
///     `fileSize` ([LegacyMediaVerificationOutcome.localFileUnreadable]
///     if the file can't even be stat'd,
///     [LegacyMediaVerificationOutcome.fileSizeMismatch] if the sizes
///     differ). Checked BEFORE any network download, so an obviously
///     wrong/missing local file never wastes a download.
///  8. `checksumSha256` is present and is exactly 64 lowercase hex
///     characters ([LegacyMediaVerificationOutcome.missingChecksum] /
///     [LegacyMediaVerificationOutcome.invalidChecksum]).
///  9. A fresh `GET /media/{id}` (never a cached/reused URL — the
///     endpoint regenerates one on every call) yields a presigned
///     download URL, and downloading it succeeds
///     ([LegacyMediaVerificationOutcome.downloadFailed] for any failure
///     at either step — fetching detail or downloading the object).
/// 10. See "How the JWT is kept off the presigned URL" below.
/// 11. The downloaded byte count equals `fileSize`
///     ([LegacyMediaVerificationOutcome.downloadedSizeMismatch]).
/// 12. SHA-256 is computed, on-device, from the downloaded bytes.
/// 13. That computed digest exactly equals `checksumSha256`
///     ([LegacyMediaVerificationOutcome.checksumMismatch]).
///
/// Only when all thirteen checks pass does [verify] return
/// [LegacyMediaVerificationOutcome.verified].
///
/// ### How the JWT is kept off the presigned URL
///
/// [MediaRepository.downloadBytes] (used for step 9's actual byte
/// transfer) is a thin passthrough to [ApiClient.downloadBytes], which
/// goes through a dedicated Dio instance that NEVER has the Bearer-JWT-
/// attaching interceptor registered on it — never the app's shared,
/// authenticated Dio. See that method's own doc for the full reasoning;
/// the short version is that a presigned URL already carries its own
/// delegated authorization and typically points at a completely
/// different host than this backend, so attaching this app's JWT to it
/// would leak an unrelated credential to a third party.
///
/// ### Memory/file-size safety
///
/// This class deliberately downloads the backend's copy fully into
/// memory (a `List<int>`) rather than streaming it to a temporary file.
/// This was a deliberate choice, not an oversight: the backend's own
/// upload limit is 25MB (`max_upload_size_mb` in
/// `backend/app/core/config.py`), a size any mobile device can safely
/// hold in memory without risk, and buffering in memory keeps this
/// class's only network dependency ([MediaRepository.downloadBytes])
/// injectable as a single async closure returning `List<int>` — exactly
/// the same "inject a closure, keep unit tests free of real I/O" pattern
/// [LegacyMediaMigrationService] already established for local file
/// reads. Streaming to a temporary file would additionally introduce a
/// new "delete this scratch file when done" responsibility this class
/// would have to get right on every exit path (including every early
/// failure return above) purely to stay memory-efficient at a size where
/// memory was never actually a practical concern — added complexity
/// without a corresponding safety benefit at this size limit. If the
/// upload size limit is ever raised substantially, this trade-off should
/// be revisited.
///
/// The ORIGINAL local file's bytes are never read by this class at all —
/// only its length (a cheap `stat`) is ever inspected (step 7). The
/// SHA-256 comparison (steps 12-13) is entirely between the backend's
/// stored digest and a fresh download of the backend's own object; this
/// class never hashes the local file's content, matching the audit
/// report's own framing: verification proves "the object currently in
/// storage is still byte-identical to what the backend recorded a hash
/// for at upload time," not "the local file was itself always valid."
///
/// ### Integration (deliberately deferred)
///
/// This phase adds no UI. [verify] is a plain, callable service method;
/// wiring a "Verify migrated media" action into
/// `LegacyMediaMigrationPage` (or a future dedicated screen) — and, far
/// more importantly, ever offering a delete action gated on its result —
/// is left to a later phase, per this phase's own scope.
class LegacyMediaVerificationService {
  LegacyMediaVerificationService({
    MediaRepository? mediaRepository,
    Future<int> Function(String path)? localFileLength,
  }) : _mediaRepository = mediaRepository ?? MediaRepository.instance,
       _localFileLength = localFileLength ?? _defaultLocalFileLength;

  /// Lazily-constructed app-wide singleton, matching
  /// `LegacyMediaMigrationService.instance`/`MediaRepository.instance`.
  /// Tests should construct `LegacyMediaVerificationService(...)`
  /// directly with injected fakes.
  static LegacyMediaVerificationService get instance =>
      _instance ??= LegacyMediaVerificationService();
  static LegacyMediaVerificationService? _instance;

  final MediaRepository _mediaRepository;
  final Future<int> Function(String path) _localFileLength;

  static Future<int> _defaultLocalFileLength(String path) =>
      File(path).length();

  static final RegExp _sha256HexPattern = RegExp(r'^[0-9a-f]{64}$');

  /// Verifies exactly one legacy Hive item — see the class doc for the
  /// full, ordered algorithm. Never throws: any exception at any step
  /// (network, HTTP, malformed response, missing field, local file
  /// error, ...) is converted to a [LegacyMediaVerificationResult] with
  /// [LegacyMediaVerificationOutcome.verified] never being one of the
  /// possible outcomes of a caught failure — verification fails closed,
  /// always.
  Future<LegacyMediaVerificationResult> verify({
    required LegacyMediaKind kind,
    required String legacyId,
    required String localFilePath,
  }) async {
    final legacySource = '${kind.legacySourcePrefix}:$legacyId';

    try {
      // Step 1: resolve the backend row. A failed/errored lookup is
      // deliberately indistinguishable here from "no such row" — both
      // are conservatively treated as "not found," never as some other,
      // more optimistic outcome.
      final MediaAssetPage page;
      try {
        page = await _mediaRepository.list(
          legacySource: legacySource,
          limit: 1,
          offset: 0,
        );
      } catch (_) {
        return _result(
          LegacyMediaVerificationOutcome.backendAssetNotFound,
          legacySource,
        );
      }
      if (page.items.isEmpty) {
        return _result(
          LegacyMediaVerificationOutcome.backendAssetNotFound,
          legacySource,
        );
      }
      final summary = page.items.first;

      // Step 2.
      if (summary.id.isEmpty) {
        return _result(
          LegacyMediaVerificationOutcome.invalidBackendId,
          legacySource,
        );
      }

      // Step 3.
      if (summary.legacySource != legacySource) {
        return _result(
          LegacyMediaVerificationOutcome.legacySourceMismatch,
          legacySource,
          backendMediaId: summary.id,
        );
      }

      // Step 4 (ownership) — see class doc: nothing to check independently here.

      // Step 5.
      if (summary.mediaType != kind.legacySourcePrefix) {
        return _result(
          LegacyMediaVerificationOutcome.mediaTypeMismatch,
          legacySource,
          backendMediaId: summary.id,
        );
      }

      // Step 6.
      if (summary.legacyCreatedAt == null) {
        return _result(
          LegacyMediaVerificationOutcome.missingLegacyCreatedAt,
          legacySource,
          backendMediaId: summary.id,
        );
      }

      // Step 7 — local file SIZE only (never its content), and only
      // AFTER every cheap, network-free backend-metadata check above has
      // already passed, so an obviously-wrong backend row never costs a
      // filesystem stat either.
      final int localSize;
      try {
        localSize = await _localFileLength(localFilePath);
      } catch (_) {
        return _result(
          LegacyMediaVerificationOutcome.localFileUnreadable,
          legacySource,
          backendMediaId: summary.id,
        );
      }
      if (localSize != summary.fileSize) {
        return _result(
          LegacyMediaVerificationOutcome.fileSizeMismatch,
          legacySource,
          backendMediaId: summary.id,
        );
      }

      // Step 8.
      final expectedChecksum = summary.checksumSha256;
      if (expectedChecksum == null) {
        return _result(
          LegacyMediaVerificationOutcome.missingChecksum,
          legacySource,
          backendMediaId: summary.id,
        );
      }
      if (!_sha256HexPattern.hasMatch(expectedChecksum)) {
        return _result(
          LegacyMediaVerificationOutcome.invalidChecksum,
          legacySource,
          backendMediaId: summary.id,
        );
      }

      // Step 9 — a FRESH presigned URL (GET /media/{id} regenerates one
      // on every call; never reuse one obtained earlier), then the
      // actual byte download.
      final MediaAssetModel detail;
      try {
        detail = await _mediaRepository.get(summary.id);
      } catch (_) {
        return _result(
          LegacyMediaVerificationOutcome.downloadFailed,
          legacySource,
          backendMediaId: summary.id,
        );
      }
      final downloadUrl = detail.downloadUrl;
      if (downloadUrl == null) {
        return _result(
          LegacyMediaVerificationOutcome.downloadFailed,
          legacySource,
          backendMediaId: summary.id,
        );
      }

      final List<int> downloadedBytes;
      try {
        downloadedBytes = await _mediaRepository.downloadBytes(downloadUrl);
      } catch (_) {
        return _result(
          LegacyMediaVerificationOutcome.downloadFailed,
          legacySource,
          backendMediaId: summary.id,
        );
      }

      // Step 11.
      if (downloadedBytes.length != summary.fileSize) {
        return _result(
          LegacyMediaVerificationOutcome.downloadedSizeMismatch,
          legacySource,
          backendMediaId: summary.id,
        );
      }

      // Steps 12-13.
      final downloadedChecksum = sha256.convert(downloadedBytes).toString();
      if (downloadedChecksum != expectedChecksum) {
        return _result(
          LegacyMediaVerificationOutcome.checksumMismatch,
          legacySource,
          backendMediaId: summary.id,
        );
      }

      return _result(
        LegacyMediaVerificationOutcome.verified,
        legacySource,
        backendMediaId: summary.id,
      );
    } catch (_) {
      // Last-resort safety net: should never be reached given every step
      // above already has its own catch, but this is what makes "verify()
      // never throws" an absolute guarantee rather than one that depends
      // on every call site above being exhaustive forever.
      return _result(
        LegacyMediaVerificationOutcome.unexpectedError,
        legacySource,
      );
    }
  }

  LegacyMediaVerificationResult _result(
    LegacyMediaVerificationOutcome outcome,
    String legacySource, {
    String? backendMediaId,
  }) => LegacyMediaVerificationResult(
    outcome: outcome,
    legacySource: legacySource,
    backendMediaId: backendMediaId,
  );
}

/// Every possible result of [LegacyMediaVerificationService.verify] — see
/// that method's doc for exactly which check produces which outcome.
/// [code] matches the exact snake_case reason-code strings from the
/// PHASE14I-H spec, for any future wire/analytics use that expects them
/// verbatim; nothing in this phase actually serializes these anywhere.
enum LegacyMediaVerificationOutcome {
  verified('verified'),
  backendAssetNotFound('backend_asset_not_found'),
  invalidBackendId('invalid_backend_id'),
  legacySourceMismatch('legacy_source_mismatch'),
  mediaTypeMismatch('media_type_mismatch'),
  missingLegacyCreatedAt('missing_legacy_created_at'),
  localFileUnreadable('local_file_unreadable'),
  fileSizeMismatch('file_size_mismatch'),
  missingChecksum('missing_checksum'),
  invalidChecksum('invalid_checksum'),
  downloadFailed('download_failed'),
  downloadedSizeMismatch('downloaded_size_mismatch'),
  checksumMismatch('checksum_mismatch'),

  /// Should never normally be reached — see [LegacyMediaVerificationService.
  /// verify]'s outer safety-net catch block.
  unexpectedError('unexpected_error');

  const LegacyMediaVerificationOutcome(this.code);

  /// The exact snake_case string for this outcome.
  final String code;
}

/// The result of one [LegacyMediaVerificationService.verify] call. Safe
/// to show to a user or log: [description] is always one of a small set
/// of fixed, human-written strings — never a raw exception message, a
/// URL (presigned or otherwise), an `object_key`, or any other
/// potentially sensitive detail.
class LegacyMediaVerificationResult {
  const LegacyMediaVerificationResult({
    required this.outcome,
    required this.legacySource,
    this.backendMediaId,
  });

  final LegacyMediaVerificationOutcome outcome;

  /// `"<kind>:<hiveId>"` — exactly what was looked up.
  final String legacySource;

  /// The backend's own id for the matched row, once one was found — i.e.
  /// non-null for every outcome except [LegacyMediaVerificationOutcome.
  /// backendAssetNotFound]/[LegacyMediaVerificationOutcome.invalidBackendId]
  /// (no valid id to report yet at that point) and
  /// [LegacyMediaVerificationOutcome.unexpectedError] (unknown how far
  /// verification actually got).
  final String? backendMediaId;

  bool get isVerified => outcome == LegacyMediaVerificationOutcome.verified;

  /// A short, fixed, non-sensitive explanation suitable for a future
  /// cleanup screen to show directly to a user.
  String get description {
    switch (outcome) {
      case LegacyMediaVerificationOutcome.verified:
        return 'Verified — the backend copy matches this device\'s file exactly.';
      case LegacyMediaVerificationOutcome.backendAssetNotFound:
        return 'No matching backend upload was found for this item.';
      case LegacyMediaVerificationOutcome.invalidBackendId:
        return 'The backend returned an invalid record for this item.';
      case LegacyMediaVerificationOutcome.legacySourceMismatch:
        return 'The backend record did not match this item\'s identity.';
      case LegacyMediaVerificationOutcome.mediaTypeMismatch:
        return 'The backend record\'s media type did not match.';
      case LegacyMediaVerificationOutcome.missingLegacyCreatedAt:
        return 'The backend record is missing its original date.';
      case LegacyMediaVerificationOutcome.localFileUnreadable:
        return 'This device\'s copy of the file could not be read.';
      case LegacyMediaVerificationOutcome.fileSizeMismatch:
        return 'The file size on this device does not match the backend record.';
      case LegacyMediaVerificationOutcome.missingChecksum:
        return 'The backend record has no integrity checksum yet.';
      case LegacyMediaVerificationOutcome.invalidChecksum:
        return 'The backend record\'s checksum is malformed.';
      case LegacyMediaVerificationOutcome.downloadFailed:
        return 'Could not download the backend copy to verify it.';
      case LegacyMediaVerificationOutcome.downloadedSizeMismatch:
        return 'The downloaded file size did not match the backend record.';
      case LegacyMediaVerificationOutcome.checksumMismatch:
        return 'The downloaded file\'s content does not match the backend record.';
      case LegacyMediaVerificationOutcome.unexpectedError:
        return 'An unexpected error occurred while verifying this item.';
    }
  }
}
