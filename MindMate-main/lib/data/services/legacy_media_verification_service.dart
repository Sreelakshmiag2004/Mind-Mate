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
///     [File.length]) equals the backend's `fileSize`
///     ([LegacyMediaVerificationOutcome.localFileUnreadable] if the file
///     can't even be stat'd, [LegacyMediaVerificationOutcome.
///     fileSizeMismatch] if the sizes differ). Checked BEFORE any local
///     file read or network call, so an obviously wrong/missing local
///     file never wastes either.
///  8. `checksumSha256` is present and is exactly 64 lowercase hex
///     characters ([LegacyMediaVerificationOutcome.missingChecksum] /
///     [LegacyMediaVerificationOutcome.invalidChecksum]).
///  9. PHASE14I-I: the LOCAL file's actual CONTENT is hashed — see
///     "Local file hashing" below — and that digest must exactly equal
///     `checksumSha256` ([LegacyMediaVerificationOutcome.localHashFailed]
///     if the file can't be read/hashed,
///     [LegacyMediaVerificationOutcome.localChecksumMismatch] if the
///     hashes differ). This is what actually closes the gap a file-size
///     match alone leaves open — two files of identical length can still
///     differ in content — and it runs BEFORE any network download, so a
///     local file that's already provably wrong never costs one.
/// 10. Only once the LOCAL file's hash has already matched does a fresh
///     `GET /media/{id}` (never a cached/reused URL — the endpoint
///     regenerates one on every call) fetch a presigned download URL,
///     and the object is actually downloaded
///     ([LegacyMediaVerificationOutcome.downloadFailed] for any failure
///     at either step).
/// 11. See "How the JWT is kept off the presigned URL" below.
/// 12. The downloaded byte count equals `fileSize`
///     ([LegacyMediaVerificationOutcome.downloadedSizeMismatch]).
/// 13. SHA-256 is computed, on-device, from the downloaded bytes.
/// 14. That computed digest exactly equals `checksumSha256`
///     ([LegacyMediaVerificationOutcome.checksumMismatch]).
///
/// Only when every check above passes does [verify] return
/// [LegacyMediaVerificationOutcome.verified] — at which point THREE
/// independent facts have all been established: the local file's hash,
/// the downloaded object's hash, and the backend's own recorded hash are
/// all identical (see "Local file hashing" below for the full three-way
/// chain this proves).
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
/// ### Local file hashing (PHASE14I-I)
///
/// PHASE14I-H proved only `SHA256(downloaded backend bytes) ==
/// backend.checksumSha256` — a size-only comparison stood in for the
/// local file's own integrity, which left a real gap: two files of
/// identical length can still differ in content, so nothing actually
/// proved the LOCAL Hive file itself matches what's stored server-side.
/// PHASE14I-I closes that gap by additionally computing
/// `SHA256(local file bytes)` (step 9) and requiring it to equal
/// `backend.checksumSha256` too. Combined with step 14's existing
/// downloaded-bytes check, [verify] now proves all three of:
///
/// ```
/// SHA256(local file bytes) == backend.checksumSha256
/// SHA256(downloaded bytes) == backend.checksumSha256
/// (transitively: SHA256(local file bytes) == SHA256(downloaded bytes))
/// ```
///
/// The local file is read via [_openLocalFileStream] (default:
/// [File.openRead], which yields the file in filesystem-sized chunks —
/// typically tens of KB at a time, never the whole file at once) piped
/// through `sha256.bind(...)` — [package:crypto]'s own `Hash` class is a
/// `dart:convert` `Converter`, and `Converter.bind` is the standard,
/// fully public Dart idiom for incremental/chunked conversion of a
/// stream: it feeds each chunk into the hash's running internal state
/// one at a time and only ever holds one chunk in memory at once,
/// regardless of how large the source file is. This is opened **read-
/// only** ([File.openRead] never opens for writing) and the file's
/// content, timestamp, name, and location are never touched — hashing a
/// file only ever reads bytes from it.
///
/// Local hashing runs BEFORE any network call (step 9, before step 10's
/// download) — a local file that already fails its checksum comparison
/// is reported [LegacyMediaVerificationOutcome.localChecksumMismatch]
/// immediately, and the backend object is never downloaded at all.
///
/// ### Memory/download-size safety
///
/// The backend's copy is still downloaded fully into memory (a
/// `List<int>`) rather than streamed to a temporary file — this remains
/// a deliberate choice from PHASE14I-H, unaffected by this phase: the
/// backend's own upload limit is 25MB (`max_upload_size_mb` in
/// `backend/app/core/config.py`), a size any mobile device can safely
/// hold in memory without risk, and buffering in memory keeps
/// [MediaRepository.downloadBytes] injectable as a single async closure
/// returning `List<int>`. The LOCAL file, by contrast, IS now read via a
/// genuinely chunked stream (see above) rather than a single
/// `readAsBytes()` call — there was no reason to accept an unbounded
/// single allocation for the one read this class performs that didn't
/// already have a good reason to be bounded (the download's own 25MB
/// cap), so local hashing uses the stronger, stream-based approach
/// throughout, per this phase's own instruction to prefer it.
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
    Stream<List<int>> Function(String path)? openLocalFileStream,
  }) : _mediaRepository = mediaRepository ?? MediaRepository.instance,
       _localFileLength = localFileLength ?? _defaultLocalFileLength,
       _openLocalFileStream = openLocalFileStream ?? _defaultOpenLocalFileStream;

  /// Lazily-constructed app-wide singleton, matching
  /// `LegacyMediaMigrationService.instance`/`MediaRepository.instance`.
  /// Tests should construct `LegacyMediaVerificationService(...)`
  /// directly with injected fakes.
  static LegacyMediaVerificationService get instance =>
      _instance ??= LegacyMediaVerificationService();
  static LegacyMediaVerificationService? _instance;

  final MediaRepository _mediaRepository;
  final Future<int> Function(String path) _localFileLength;

  /// PHASE14I-I. Injectable purely so a test can supply a controlled,
  /// observably-multi-chunk `Stream<List<int>>` without a real file on
  /// disk — production always uses [File.openRead], which reads the file
  /// **read-only** and yields it in filesystem-sized chunks.
  final Stream<List<int>> Function(String path) _openLocalFileStream;

  static Future<int> _defaultLocalFileLength(String path) =>
      File(path).length();

  static Stream<List<int>> _defaultOpenLocalFileStream(String path) =>
      File(path).openRead();

  static final RegExp _sha256HexPattern = RegExp(r'^[0-9a-f]{64}$');

  /// PHASE14I-I. Hashes [stream] incrementally via `sha256.bind` (see the
  /// class doc, "Local file hashing") — never buffers the whole source
  /// into one `List<int>` first. Used for BOTH the local file (via
  /// [_openLocalFileStream]) and, for symmetry/consistency, could equally
  /// hash any other byte stream; today it is only ever called with the
  /// local file's stream, since the downloaded backend bytes already
  /// arrive as a single in-memory `List<int>` (see "Memory/download-size
  /// safety") and are hashed directly with `sha256.convert`.
  static Future<String> _hashStream(Stream<List<int>> stream) async {
    final digest = await sha256.bind(stream).single;
    return digest.toString();
  }

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

      // Step 9 (PHASE14I-I) — hash the LOCAL file's actual content,
      // incrementally (see the class doc, "Local file hashing"), and
      // require it to already match the backend's checksum BEFORE ever
      // attempting a network download. This is the check that actually
      // closes the "size matched, but were the bytes really the same?"
      // gap a file-size comparison alone leaves open.
      final String localChecksum;
      try {
        localChecksum = await _hashStream(_openLocalFileStream(localFilePath));
      } catch (_) {
        return _result(
          LegacyMediaVerificationOutcome.localHashFailed,
          legacySource,
          backendMediaId: summary.id,
        );
      }
      if (localChecksum != expectedChecksum) {
        return _result(
          LegacyMediaVerificationOutcome.localChecksumMismatch,
          legacySource,
          backendMediaId: summary.id,
        );
      }

      // Step 10 — a FRESH presigned URL (GET /media/{id} regenerates one
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

      // Step 12.
      if (downloadedBytes.length != summary.fileSize) {
        return _result(
          LegacyMediaVerificationOutcome.downloadedSizeMismatch,
          legacySource,
          backendMediaId: summary.id,
        );
      }

      // Steps 13-14.
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

  /// PHASE14I-I. The local file could not be read/hashed — e.g. a
  /// permissions error or a read failure partway through, distinct from
  /// [localFileUnreadable] (which means the file couldn't even be
  /// stat'd for its size, one step earlier).
  localHashFailed('local_hash_failed'),

  /// PHASE14I-I. `SHA256(local file bytes) != backend.checksumSha256` —
  /// the local file has the RIGHT size but the WRONG content. This is
  /// the specific check that proves size equality alone can never be
  /// enough to consider an item safe to clean up.
  localChecksumMismatch('local_checksum_mismatch'),

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
      case LegacyMediaVerificationOutcome.localHashFailed:
        return 'This device\'s copy of the file could not be verified.';
      case LegacyMediaVerificationOutcome.localChecksumMismatch:
        return 'This device\'s file does not match the backend record\'s content.';
      case LegacyMediaVerificationOutcome.downloadFailed:
        return 'Could not download the backend copy to verify it.';
      case LegacyMediaVerificationOutcome.downloadedSizeMismatch:
        return 'The downloaded file size did not match the backend record.';
      case LegacyMediaVerificationOutcome.checksumMismatch:
        return 'The downloaded backend copy\'s content does not match the backend record.';
      case LegacyMediaVerificationOutcome.unexpectedError:
        return 'An unexpected error occurred while verifying this item.';
    }
  }
}
