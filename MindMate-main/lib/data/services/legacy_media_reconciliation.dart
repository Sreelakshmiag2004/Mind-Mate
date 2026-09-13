/// PHASE14I-F — display-only reconciliation between backend-hosted media
/// and pre-existing, not-yet-cleaned-up legacy Hive records.
///
/// `LegacyMediaMigrationService` (PHASE14I-C) uploads a legacy Hive item
/// to the backend WITHOUT ever touching the original Hive record — by
/// design, so the migration itself stays safe to interrupt/retry (see
/// that class's own doc). The unavoidable side effect is that
/// `vault.dart`/`viewall_images.dart`/`viewall_videos.dart`'s existing
/// merge logic (backend items + Hive items, concatenated) then shows the
/// same item twice once it's been migrated: once as the new backend
/// `MediaAssetModel`, once as the untouched legacy Hive record. This file
/// is the fix for exactly that display problem — nothing else.
///
/// This is display reconciliation only:
///  * No Hive record, Hive box, or local file is ever read for writing,
///    deleted, or modified by anything in this file — every function
///    here is pure (takes lists in, returns a new filtered list out).
///  * No new migration/tracking mechanism is introduced — matching is
///    done by comparing `MediaAssetModel.legacySource` (a field the
///    backend and `LegacyMediaMigrationService` already populate) against
///    an expected `"<kind>:<hiveId>"` string built from [LegacyMediaKind]
///    (the same enum the migration service already uses for its own
///    prefixes — re-exported here rather than redefined, so there is
///    exactly one source of truth for what those three prefix strings
///    are).
library;

import '../models/media/media_asset_model.dart';
import 'legacy_media_migration_service.dart' show LegacyMediaKind;

export 'legacy_media_migration_service.dart' show LegacyMediaKind;

/// The identity-safety rule from PHASE14I-C.1's
/// `LegacyMediaMigrationService._isValidSuccessfulAsset`, reproduced here
/// (that method is private to its own file, and this phase's own
/// instruction is to leave the migration service untouched rather than
/// make it public) rather than re-derived differently: [asset] counts as
/// a genuine migrated match for [expectedLegacySource] only if it has a
/// non-empty backend id AND its `legacySource` is an EXACT match — never
/// a title, filename, date, list position, or backend UUID comparison.
/// Kept in sync with the migration service's own copy by hand; if that
/// rule ever changes, this one must change with it.
bool isValidMigratedAsset(MediaAssetModel asset, String expectedLegacySource) =>
    asset.id.isNotEmpty && asset.legacySource == expectedLegacySource;

/// Returns the subset of [legacyItems] that should still be displayed —
/// i.e. every item that does NOT have a valid, corresponding migrated
/// [MediaAssetModel] in [remoteItems]. An item is suppressed (left out of
/// the returned list) only when [remoteItems] contains an asset whose
/// `legacySource` exactly equals `"<kind.legacySourcePrefix>:<hiveId>"`
/// (via [legacyIdOf]) AND [isValidMigratedAsset] holds for it.
///
/// [legacyItems] and its items' own Hive-record identity are never
/// mutated, and nothing here reads or writes any Hive box or the
/// filesystem — this only ever filters the in-memory list a caller
/// already built (typically `box.values.toList()`, itself unmodified
/// either way).
///
/// A [remoteItems] entry with a `null`/mismatched/empty-id `legacySource`
/// simply never matches anything and is otherwise ignored here — callers
/// are expected to already be merging `remoteItems` into their displayed
/// list separately (this function only ever decides which LEGACY items to
/// keep, never which remote items to show).
List<T> suppressMigratedLegacyItems<T>({
  required List<T> legacyItems,
  required List<MediaAssetModel> remoteItems,
  required LegacyMediaKind kind,
  required String Function(T item) legacyIdOf,
}) {
  if (legacyItems.isEmpty || remoteItems.isEmpty) return legacyItems;

  // Indexed by the exact legacySource string — never by title, filename,
  // date, or the asset's own backend id — so a later per-item lookup is
  // an exact-string match, not a fuzzy/heuristic one. Multiple remote
  // assets sharing one legacySource can't happen (the backend's
  // `(user_id, legacy_source)` partial unique index forbids it — see
  // `backend/app/models/media_asset.py`); if it somehow did, the last one
  // wins here, which is harmless since [isValidMigratedAsset] is
  // re-checked per lookup regardless of which one that is.
  final byLegacySource = <String, MediaAssetModel>{
    for (final asset in remoteItems)
      if (asset.legacySource != null) asset.legacySource!: asset,
  };

  return legacyItems.where((item) {
    final expectedLegacySource =
        '${kind.legacySourcePrefix}:${legacyIdOf(item)}';
    final candidate = byLegacySource[expectedLegacySource];
    final isMigrated =
        candidate != null &&
        isValidMigratedAsset(candidate, expectedLegacySource);
    return !isMigrated;
  }).toList();
}
