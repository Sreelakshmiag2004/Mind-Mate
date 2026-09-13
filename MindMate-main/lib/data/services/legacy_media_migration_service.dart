import 'dart:io';

import 'package:hive/hive.dart';

import '../../core/network/api_exception.dart';
import '../../image_note.dart';
import '../../vault.dart'
    show
        VoiceNote,
        imageContentTypeForFilename,
        kMaxImageUploadBytes,
        voiceContentTypeForFilename,
        kMaxVoiceUploadBytes,
        videoContentTypeForFilename,
        kMaxVideoUploadBytes;
import '../../video_note.dart';
import '../models/media/media_asset_model.dart';
import '../repositories/media_repository.dart';

/// PHASE14I-C — the Flutter-side legacy Hive media migration runner.
///
/// Migrates pre-existing `image_notes`/`voice_notes`/`video_notes` Hive
/// records (the ones left behind by PHASE14F/G/H's cutover — see those
/// phases' own `_VaultImage.legacy`/`_VoiceItem.legacy`/`_VaultVideo.legacy`
/// — new media created after those phases never touches Hive at all) into
/// real backend `MediaAsset`s, using the duplicate-safe `legacy_source`
/// contract PHASE14I-B added server-side
/// (`backend/app/services/media_service.py`, `backend/app/schemas/
/// media.py`).
///
/// ### What this class is NOT
///
/// * **Not a UI.** No screen calls this yet (per this phase's own
///   instruction) — it exists purely as a clean entry point for a future
///   Vault migration screen to call from an explicit, user-initiated
///   action (e.g. a "Migrate my Vault" button). Nothing in `main.dart` or
///   `vault.dart`'s `initState` calls it, and nothing here schedules
///   itself to run automatically, in the background, or silently — see
///   the class-level safety notes below.
/// * **Not a second migration-status database.** This deliberately keeps
///   no local record of "which items have been migrated" — see
///   [_migrateItem]'s duplicate-check step, which always asks the
///   backend (`GET /media?legacy_source=...`) rather than a local flag.
///   That is what makes every run of [run] safe to interrupt and safe to
///   repeat: resuming after a partial run (or simply running it again
///   after a full one) just re-asks the server per item, which is cheap,
///   and never re-uploads an item the server already has.
/// * **Not a Hive/file deletion tool.** Nothing in this file ever calls
///   `.delete()` on a Hive record or deletes a local file — migrating an
///   item to the backend does not remove its Hive record or the file it
///   points at. A pre-existing legacy item keeps showing up via its
///   `_VaultImage.legacy`/`_VoiceItem.legacy`/`_VaultVideo.legacy` path
///   exactly as before; deciding whether/when to ever clean those up is
///   explicitly out of scope for this phase.
/// * **Not a Firebase downloader.** A legacy `VoiceNote.url` (the old
///   Firebase Storage download URL some pre-PHASE14G recordings carry) is
///   never read or fetched here — only [VoiceNote.localPath] (a file this
///   device already has) is ever uploaded. An item whose local file is
///   missing is reported as [LegacyMigrationOutcome.skippedFileMissing],
///   never silently re-fetched from Firebase — see the class doc's
///   "Known limitation" below.
///
/// ### Ordering, idempotency, and resumability
///
/// [run] always processes images, then voice notes, then videos, in that
/// fixed order (per this phase's spec) — never interleaved, and never
/// starting the next kind until the previous one has finished processing
/// every item it found (or the run was cancelled). Within one kind, items
/// are processed one at a time; a single item's failure (a 4xx/5xx, a
/// missing file, an unsupported type, an oversized file) is recorded in
/// its own [LegacyMigrationItemResult] and never stops the rest of that
/// kind's items, or the kinds after it, from being attempted.
///
/// Every item's fate rests on exactly one server-side fact: does a
/// `MediaAsset` with this user's `(user_id, legacy_source)` already exist
/// (PHASE14I-B's partial unique index)? [_migrateItem] checks that first,
/// via a plain `GET /media?legacy_source=...`, before ever reading the
/// local file or uploading anything — so an item already migrated in a
/// prior run costs one cheap metadata request here, never a second byte
/// of the file being re-uploaded, re-decoded, or re-stored. If, in a true
/// race, two calls to [run] (or two devices signed into the same account)
/// attempt the very same item at once and both pass that check, the
/// backend's own unique-index backstop (not anything in this class)
/// guarantees only one of the two uploads actually creates a row — see
/// `backend/app/services/media_service.py`'s module docstring.
///
/// ### Cancellation
///
/// [isCancelled] is polled only *between* items — never during a single
/// item's own upload/rename calls, which always run to completion (success
/// or failure) once started. This is what "safe to interrupt" means here:
/// an interrupt can only ever stop the *next* item from starting, never
/// leave the current one half-uploaded.
///
/// ### Success contract (PHASE14I-C.1)
///
/// [LegacyMigrationOutcome.migrated] and [LegacyMigrationOutcome.
/// alreadyMigrated] are never reported on the strength of "the call
/// returned without throwing" alone. Before either outcome is returned,
/// [_isValidSuccessfulAsset] checks that the resolved/returned
/// [MediaAssetModel] actually has a non-empty [MediaAssetModel.id] AND a
/// [MediaAssetModel.legacySource] equal to the exact `legacySource` this
/// item looked up/sent. A response that fails that check (a malformed
/// body, or — even though nothing in this codebase should ever produce
/// one — a mismatched row) is reported as [LegacyMigrationOutcome.failed]
/// instead: this class would rather under-report success than tell a
/// future migration screen an item is safely on the server when the
/// evidence for that doesn't actually hold up. This check runs
/// independently at both success sites — the duplicate-check lookup and
/// the upload response — never assumed transitively from one to the
/// other.
///
/// ### Known limitation
///
/// A legacy voice note recorded before PHASE14G was, at the time, also
/// uploaded to Firebase Storage (`VoiceNote.url`) as well as saved
/// locally (`VoiceNote.localPath`) — see `vault.dart`'s pre-PHASE14G
/// history. If that local file has since been deleted (device storage
/// cleared, app reinstalled, ...), this class has no way to recover it:
/// per this phase's explicit instruction not to touch Firebase code, this
/// class never attempts to download `VoiceNote.url` as a fallback. Such
/// an item is reported as [LegacyMigrationOutcome.skippedFileMissing] and
/// left exactly as it was — a future phase would have to add a Firebase
/// fallback download path deliberately, as its own decision.
class LegacyMediaMigrationService {
  LegacyMediaMigrationService({
    MediaRepository? mediaRepository,
    List<ImageNote> Function()? imageNotesProvider,
    List<VoiceNote> Function()? voiceNotesProvider,
    List<VideoNote> Function()? videoNotesProvider,
    Future<bool> Function(String path)? fileExists,
    Future<List<int>> Function(String path)? readFileBytes,
  }) : _mediaRepository = mediaRepository ?? MediaRepository.instance,
       _imageNotesProvider = imageNotesProvider ?? _defaultImageNotes,
       _voiceNotesProvider = voiceNotesProvider ?? _defaultVoiceNotes,
       _videoNotesProvider = videoNotesProvider ?? _defaultVideoNotes,
       _fileExists = fileExists ?? _defaultFileExists,
       _readFileBytes = readFileBytes ?? _defaultReadFileBytes;

  /// Lazily-constructed app-wide singleton, matching
  /// `MediaRepository.instance`/`VaultLockRepository.instance`. Tests
  /// should construct `LegacyMediaMigrationService(...)` directly with
  /// injected fakes (see the constructor's optional parameters) rather
  /// than touching real Hive boxes or the real filesystem.
  static LegacyMediaMigrationService get instance =>
      _instance ??= LegacyMediaMigrationService();
  static LegacyMediaMigrationService? _instance;

  final MediaRepository _mediaRepository;
  final List<ImageNote> Function() _imageNotesProvider;
  final List<VoiceNote> Function() _voiceNotesProvider;
  final List<VideoNote> Function() _videoNotesProvider;
  final Future<bool> Function(String path) _fileExists;
  final Future<List<int>> Function(String path) _readFileBytes;

  /// Reads `Hive.box<ImageNote>('image_notes')` — already opened once in
  /// `main.dart` before `runApp`, exactly like `schedulerBox`
  /// (untouched by this class entirely) and the voice/video boxes below.
  /// `.toList()` takes a snapshot so a concurrent Hive write during a run
  /// (nothing in the app performs one — see the class doc's "not a
  /// deletion tool" note) can't mutate the list this method is iterating.
  static List<ImageNote> _defaultImageNotes() =>
      Hive.box<ImageNote>('image_notes').values.toList();
  static List<VoiceNote> _defaultVoiceNotes() =>
      Hive.box<VoiceNote>('voice_notes').values.toList();
  static List<VideoNote> _defaultVideoNotes() =>
      Hive.box<VideoNote>('video_notes').values.toList();

  static Future<bool> _defaultFileExists(String path) => File(path).exists();
  static Future<List<int>> _defaultReadFileBytes(String path) =>
      File(path).readAsBytes();

  /// Runs the full migration: every pending `image_notes` record, then
  /// every pending `voice_notes` record, then every pending `video_notes`
  /// record — see the class doc for exactly what "pending" means and why
  /// the ordering is fixed.
  ///
  /// [onItemResult], when given, is called once per item — as soon as
  /// that item's outcome is decided — so a future screen can render live
  /// progress ("12 of 40 migrated...") without waiting for the whole
  /// batch. [isCancelled], when given, is polled between items (see the
  /// class doc, "Cancellation"); once it returns `true`, no further items
  /// are attempted and the returned [LegacyMigrationSummary.cancelled] is
  /// `true`.
  ///
  /// [dryRun] (default `false`) performs every duplicate-check but never
  /// reads a local file, never uploads, and never renames anything —
  /// every not-yet-migrated item comes back as
  /// [LegacyMigrationOutcome.pending] instead of actually being migrated.
  /// This is the "how many items are left, and which ones" preview a
  /// future screen can show before the user commits to actually running
  /// the migration — entirely server-derived (a handful of
  /// `GET /media?legacy_source=...` calls), never a local guess based on
  /// Hive record counts alone, and with zero side effects of its own.
  Future<LegacyMigrationSummary> run({
    void Function(LegacyMigrationItemResult result)? onItemResult,
    bool Function()? isCancelled,
    bool dryRun = false,
  }) async {
    final results = <LegacyMigrationItemResult>[];
    var cancelled = false;

    Future<void> processStage<T>(
      List<T> notes,
      Future<LegacyMigrationItemResult> Function(T note) migrateOne,
    ) async {
      for (final note in notes) {
        if (isCancelled?.call() ?? false) {
          cancelled = true;
          return;
        }
        final result = await migrateOne(note);
        results.add(result);
        onItemResult?.call(result);
      }
    }

    await processStage<ImageNote>(
      _imageNotesProvider(),
      (note) => _migrateImageNote(note, dryRun: dryRun),
    );
    if (!cancelled) {
      await processStage<VoiceNote>(
        _voiceNotesProvider(),
        (note) => _migrateVoiceNote(note, dryRun: dryRun),
      );
    }
    if (!cancelled) {
      await processStage<VideoNote>(
        _videoNotesProvider(),
        (note) => _migrateVideoNote(note, dryRun: dryRun),
      );
    }

    return LegacyMigrationSummary(results: results, cancelled: cancelled);
  }

  Future<LegacyMigrationItemResult> _migrateImageNote(
    ImageNote note, {
    required bool dryRun,
  }) => _migrateItem(
    kind: LegacyMediaKind.image,
    legacyId: note.id,
    title: note.title,
    legacyDate: note.date,
    localPath: note.path,
    contentTypeForFilename: imageContentTypeForFilename,
    maxUploadBytes: kMaxImageUploadBytes,
    dryRun: dryRun,
  );

  Future<LegacyMigrationItemResult> _migrateVoiceNote(
    VoiceNote note, {
    required bool dryRun,
  }) => _migrateItem(
    kind: LegacyMediaKind.voice,
    legacyId: note.id,
    title: note.title,
    legacyDate: note.date,
    localPath: note.localPath,
    contentTypeForFilename: voiceContentTypeForFilename,
    maxUploadBytes: kMaxVoiceUploadBytes,
    durationSeconds: note.duration.inSeconds,
    dryRun: dryRun,
  );

  Future<LegacyMigrationItemResult> _migrateVideoNote(
    VideoNote note, {
    required bool dryRun,
  }) => _migrateItem(
    kind: LegacyMediaKind.video,
    legacyId: note.id,
    title: note.title,
    legacyDate: note.date,
    localPath: note.path,
    contentTypeForFilename: videoContentTypeForFilename,
    maxUploadBytes: kMaxVideoUploadBytes,
    dryRun: dryRun,
  );

  /// The one shared implementation every `_migrateXNote` method above
  /// funnels through — see the class doc for the full ordering/duplicate-
  /// check/cancellation contract this implements. Never throws: every
  /// failure this method can observe (a missing file, an unsupported
  /// type, an oversized file, or any [ApiException]) is captured into the
  /// returned [LegacyMigrationItemResult] instead, so one item's failure
  /// can never abort [run]'s loop over the rest.
  Future<LegacyMigrationItemResult> _migrateItem({
    required LegacyMediaKind kind,
    required String legacyId,
    required String title,
    required DateTime legacyDate,
    required String localPath,
    required String? Function(String filename) contentTypeForFilename,
    required int maxUploadBytes,
    required bool dryRun,
    int? durationSeconds,
  }) async {
    final legacySource = '${kind.legacySourcePrefix}:$legacyId';

    // Step 1 — ALWAYS ask the backend first, before touching the local
    // file at all. This is the entire "server-derived, no local
    // migration-status database" contract: whether this item still needs
    // migrating is a fact this class never remembers itself.
    final MediaAssetPage existingPage;
    try {
      existingPage = await _mediaRepository.list(
        legacySource: legacySource,
        limit: 1,
        offset: 0,
      );
    } on ApiException catch (error) {
      return LegacyMigrationItemResult(
        kind: kind,
        legacyId: legacyId,
        legacySource: legacySource,
        title: title,
        outcome: LegacyMigrationOutcome.failed,
        error: error,
      );
    }

    if (existingPage.items.isNotEmpty) {
      final existing = existingPage.items.first;
      if (!_isValidSuccessfulAsset(existing, legacySource)) {
        return LegacyMigrationItemResult(
          kind: kind,
          legacyId: legacyId,
          legacySource: legacySource,
          title: title,
          outcome: LegacyMigrationOutcome.failed,
          error: StateError(
            'GET /media?legacy_source=$legacySource returned an asset that '
            'does not satisfy the success contract (id=${existing.id}, '
            'legacySource=${existing.legacySource}) — refusing to report '
            'alreadyMigrated.',
          ),
        );
      }
      return LegacyMigrationItemResult(
        kind: kind,
        legacyId: legacyId,
        legacySource: legacySource,
        title: title,
        outcome: LegacyMigrationOutcome.alreadyMigrated,
        asset: existing,
      );
    }

    if (dryRun) {
      return LegacyMigrationItemResult(
        kind: kind,
        legacyId: legacyId,
        legacySource: legacySource,
        title: title,
        outcome: LegacyMigrationOutcome.pending,
      );
    }

    // Step 2 — the local file. `_basenameOf` intentionally mirrors
    // `pickedFilename`'s role in `vault.dart`'s own `_uploadImage`/
    // `_uploadVoiceNote`/`_uploadVideo`: a display-only name sent to the
    // backend as `original_filename`, whose extension also drives the
    // content-type check right below — never trusted for anything else.
    final filename = _basenameOf(localPath);

    if (!await _fileExists(localPath)) {
      return LegacyMigrationItemResult(
        kind: kind,
        legacyId: legacyId,
        legacySource: legacySource,
        title: title,
        outcome: LegacyMigrationOutcome.skippedFileMissing,
      );
    }

    final contentType = contentTypeForFilename(filename);
    if (contentType == null) {
      return LegacyMigrationItemResult(
        kind: kind,
        legacyId: legacyId,
        legacySource: legacySource,
        title: title,
        outcome: LegacyMigrationOutcome.skippedUnsupportedType,
      );
    }

    final List<int> bytes;
    try {
      bytes = await _readFileBytes(localPath);
    } catch (error) {
      return LegacyMigrationItemResult(
        kind: kind,
        legacyId: legacyId,
        legacySource: legacySource,
        title: title,
        outcome: LegacyMigrationOutcome.failed,
        error: error,
      );
    }

    // Client-side pre-check only, matching every existing upload flow's
    // own `kMax*UploadBytes` check — the backend's 413 remains the actual
    // authority; this just avoids a wasted read+upload for an obviously
    // oversized legacy file.
    if (bytes.length > maxUploadBytes) {
      return LegacyMigrationItemResult(
        kind: kind,
        legacyId: legacyId,
        legacySource: legacySource,
        title: title,
        outcome: LegacyMigrationOutcome.skippedTooLarge,
      );
    }

    // Step 3 — upload. `legacySource`/`legacyDate` here are what make
    // this call idempotent server-side even if two runs (or this run
    // retried after step 1's check) race each other — see the class doc.
    final MediaAssetModel created;
    try {
      created = await _mediaRepository.upload(
        fileBytes: bytes,
        filename: filename,
        contentType: contentType,
        durationSeconds: durationSeconds,
        legacySource: legacySource,
        legacyCreatedAt: legacyDate,
      );
    } on ApiException catch (error) {
      return LegacyMigrationItemResult(
        kind: kind,
        legacyId: legacyId,
        legacySource: legacySource,
        title: title,
        outcome: LegacyMigrationOutcome.failed,
        error: error,
      );
    }

    if (!_isValidSuccessfulAsset(created, legacySource)) {
      return LegacyMigrationItemResult(
        kind: kind,
        legacyId: legacyId,
        legacySource: legacySource,
        title: title,
        outcome: LegacyMigrationOutcome.failed,
        error: StateError(
          'POST /media/upload for legacy_source=$legacySource returned an '
          'asset that does not satisfy the success contract (id=${created.id}, '
          'legacySource=${created.legacySource}) — refusing to report migrated, '
          'and skipping the rename step.',
        ),
      );
    }

    // Step 4 — best-effort rename to the legacy item's own title (the
    // upload endpoint itself has no title field — same two-step shape as
    // every existing `_uploadImage`/`_uploadVoiceNote`/`_uploadVideo`). A
    // failed rename does NOT make this item's migration a failure: the
    // file is safely uploaded and durably associated with this
    // `legacy_source` either way, so a future run would see it as already
    // migrated rather than retry it. Legacy titles are always non-blank
    // (`ImageNote`/`VoiceNote`/`VideoNote.title` is a non-nullable
    // `String`), so no blank check is needed the way the interactive
    // upload flows' own titles sometimes require.
    var result = created;
    try {
      result = await _mediaRepository.rename(mediaId: created.id, title: title);
    } on ApiException {
      // Intentionally swallowed — see the paragraph above.
    }

    return LegacyMigrationItemResult(
      kind: kind,
      legacyId: legacyId,
      legacySource: legacySource,
      title: title,
      outcome: LegacyMigrationOutcome.migrated,
      asset: result,
    );
  }

  /// Splits on both `/` and `\` rather than depending on `package:path`
  /// (not a dependency of this project — every existing content-type
  /// helper in `vault.dart` already does its own minimal filename
  /// splitting rather than pulling it in) so this behaves the same
  /// whether a legacy record's path was ever written on Android/iOS
  /// (`/`) or, during development, Windows (`\`).
  static String _basenameOf(String path) {
    final normalized = path.replaceAll('\\', '/');
    final lastSlash = normalized.lastIndexOf('/');
    return lastSlash == -1 ? normalized : normalized.substring(lastSlash + 1);
  }

  /// PHASE14I-C.1 — the success contract described in the class doc. Both
  /// call sites in [_migrateItem] pass the exact `legacySource` THIS item
  /// looked up/sent, never a value read back off [asset] itself, so a
  /// response that silently swapped in a different item's data can't
  /// pass by comparing against itself.
  static bool _isValidSuccessfulAsset(
    MediaAssetModel asset,
    String expectedLegacySource,
  ) => asset.id.isNotEmpty && asset.legacySource == expectedLegacySource;
}

/// Which legacy Hive box an item came from — also exactly the prefix used
/// in its `legacy_source` (`"image:..."`/`"voice:..."`/`"video:..."`),
/// matching the backend's own `MEDIA_TYPES`
/// (`backend/app/models/media_asset.py`) and the fixed processing order
/// [LegacyMediaMigrationService.run] uses.
enum LegacyMediaKind {
  image('image'),
  voice('voice'),
  video('video');

  const LegacyMediaKind(this.legacySourcePrefix);

  /// The exact string used before the `:` in this kind's `legacy_source`.
  final String legacySourcePrefix;
}

/// What happened to one legacy Hive record during a [LegacyMediaMigrationService.run].
enum LegacyMigrationOutcome {
  /// Uploaded and durably recorded server-side just now, in this call.
  migrated,

  /// The backend already had a `MediaAsset` for this exact
  /// `(user_id, legacy_source)` — from an earlier run, a concurrent run,
  /// or another device on the same account. Nothing was uploaded; [
  /// LegacyMigrationItemResult.asset] is the existing row.
  alreadyMigrated,

  /// [LegacyMediaMigrationService.run] was called with `dryRun: true` and
  /// this item is NOT already migrated — i.e., a real run would attempt
  /// it. No file was read and nothing was uploaded.
  pending,

  /// The local file this Hive record points at doesn't exist on this
  /// device — see the class doc's "Known limitation" for why this is
  /// never automatically retried from a Firebase fallback.
  skippedFileMissing,

  /// The file's extension isn't one the backend's upload allow-list
  /// accepts for this [LegacyMediaKind] (mirrors `imageContentTypeForFilename`
  /// / `voiceContentTypeForFilename` / `videoContentTypeForFilename`
  /// returning `null` in the interactive upload flows).
  skippedUnsupportedType,

  /// The file exceeds this kind's `kMax*UploadBytes` client-side check.
  skippedTooLarge,

  /// The duplicate-check or the upload call itself failed (any
  /// [ApiException] — network, 401, 413, 415, 422, 5xx, ...), or the
  /// local file could not be read for a reason other than not existing
  /// (e.g. a permissions error). See [LegacyMigrationItemResult.error].
  failed,
}

/// One [LegacyMediaMigrationService.run] item's result — see
/// [LegacyMigrationOutcome] for what each outcome means.
class LegacyMigrationItemResult {
  const LegacyMigrationItemResult({
    required this.kind,
    required this.legacyId,
    required this.legacySource,
    required this.title,
    required this.outcome,
    this.asset,
    this.error,
  });

  final LegacyMediaKind kind;

  /// The Hive record's own `.id` field (never the Hive box's internal
  /// auto-increment key) — the same value embedded in [legacySource].
  final String legacyId;

  /// `"<kind>:<legacyId>"` — exactly what was sent as/looked up by
  /// `legacy_source`.
  final String legacySource;

  /// The legacy record's own title at the time this item was processed.
  final String title;

  final LegacyMigrationOutcome outcome;

  /// Non-null exactly when [outcome] is [LegacyMigrationOutcome.migrated]
  /// or [LegacyMigrationOutcome.alreadyMigrated].
  final MediaAssetModel? asset;

  /// Non-null exactly when [outcome] is [LegacyMigrationOutcome.failed].
  final Object? error;
}

/// The result of one full [LegacyMediaMigrationService.run] call.
class LegacyMigrationSummary {
  const LegacyMigrationSummary({
    required this.results,
    required this.cancelled,
  });

  /// Every item processed before the run finished or was cancelled, in
  /// the fixed images -> voice -> videos order — an item [run] never got
  /// to (because [cancelled] became true first) simply isn't in this list
  /// at all, which is enough on its own to resume: a later [run] call
  /// re-derives "what's left" from the server exactly the same way,
  /// needing no record of where this particular run stopped.
  final List<LegacyMigrationItemResult> results;

  /// `true` if `isCancelled` returned `true` before every item was
  /// processed — see [LegacyMediaMigrationService.run]'s "Cancellation"
  /// doc.
  final bool cancelled;

  int get migratedCount => _count(LegacyMigrationOutcome.migrated);
  int get alreadyMigratedCount =>
      _count(LegacyMigrationOutcome.alreadyMigrated);
  int get pendingCount => _count(LegacyMigrationOutcome.pending);
  int get failedCount => _count(LegacyMigrationOutcome.failed);
  int get skippedCount =>
      _count(LegacyMigrationOutcome.skippedFileMissing) +
      _count(LegacyMigrationOutcome.skippedUnsupportedType) +
      _count(LegacyMigrationOutcome.skippedTooLarge);

  bool get hasFailures => failedCount > 0;

  int _count(LegacyMigrationOutcome outcome) =>
      results.where((r) => r.outcome == outcome).length;
}
