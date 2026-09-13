import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/data/models/media/media_asset_model.dart';
import 'package:mindmate/data/services/legacy_media_reconciliation.dart';
import 'package:mindmate/image_note.dart';
import 'package:mindmate/vault.dart' show VoiceNote;
import 'package:mindmate/video_note.dart';

/// PHASE14I-F. These tests exercise [suppressMigratedLegacyItems]/
/// [isValidMigratedAsset] directly against plain, never-boxed
/// `ImageNote`/`VoiceNote`/`VideoNote` instances and `MediaAssetModel`
/// values — no Hive box, no widget tree, no network. The three real
/// `vault.dart`/`viewall_images.dart`/`viewall_videos.dart` merge sites
/// are thin, three-line call sites around this same function (see the
/// implementation report), so this is where the actual matching logic is
/// exhaustively covered.
void main() {
  ImageNote image({
    String id = 'img1',
    String title = 'A',
    String path = '/a.png',
  }) => ImageNote(id: id, path: path, title: title, date: DateTime(2020, 1, 1));

  VoiceNote voice({
    String id = 'voice1',
    String title = 'V',
    String localPath = '/a.m4a',
  }) => VoiceNote(
    id: id,
    title: title,
    url: 'https://firebase.example/old.m4a',
    localPath: localPath,
    date: DateTime(2020, 1, 1),
    duration: const Duration(seconds: 5),
  );

  VideoNote video({
    String id = 'vid1',
    String title = 'Vid',
    String path = '/a.mp4',
  }) => VideoNote(id: id, path: path, title: title, date: DateTime(2020, 1, 1));

  MediaAssetModel remoteAsset({
    String id = 'server-id',
    String mediaType = 'image',
    String? legacySource,
  }) => MediaAssetModel(
    id: id,
    mediaType: mediaType,
    contentType: 'image/png',
    fileSize: 5,
    createdAt: DateTime.utc(2025, 1, 1),
    legacySource: legacySource,
  );

  group('isValidMigratedAsset', () {
    test('true for a non-empty id and an exact legacySource match', () {
      final asset = remoteAsset(id: 'abc', legacySource: 'image:img1');
      expect(isValidMigratedAsset(asset, 'image:img1'), isTrue);
    });

    test('false for an empty id even with a matching legacySource', () {
      final asset = remoteAsset(id: '', legacySource: 'image:img1');
      expect(isValidMigratedAsset(asset, 'image:img1'), isFalse);
    });

    test('false for a mismatched legacySource even with a non-empty id', () {
      final asset = remoteAsset(id: 'abc', legacySource: 'image:someone-else');
      expect(isValidMigratedAsset(asset, 'image:img1'), isFalse);
    });
  });

  group('one appearance per migrated item — one test per media type', () {
    test('a migrated image is suppressed from the legacy list', () {
      final result = suppressMigratedLegacyItems(
        legacyItems: [image(id: 'img1')],
        remoteItems: [
          remoteAsset(mediaType: 'image', legacySource: 'image:img1'),
        ],
        kind: LegacyMediaKind.image,
        legacyIdOf: (n) => n.id,
      );

      expect(
        result,
        isEmpty,
      ); // suppressed — the remote copy is the only one shown
    });

    test('a migrated voice note is suppressed from the legacy list', () {
      final result = suppressMigratedLegacyItems(
        legacyItems: [voice(id: 'voice1')],
        remoteItems: [
          remoteAsset(mediaType: 'voice', legacySource: 'voice:voice1'),
        ],
        kind: LegacyMediaKind.voice,
        legacyIdOf: (n) => n.id,
      );

      expect(result, isEmpty);
    });

    test('a migrated video is suppressed from the legacy list', () {
      final result = suppressMigratedLegacyItems(
        legacyItems: [video(id: 'vid1')],
        remoteItems: [
          remoteAsset(mediaType: 'video', legacySource: 'video:vid1'),
        ],
        kind: LegacyMediaKind.video,
        legacyIdOf: (n) => n.id,
      );

      expect(result, isEmpty);
    });
  });

  group('items that must NOT be suppressed', () {
    test(
      'an unmigrated Hive item (no matching remote asset at all) remains visible',
      () {
        final result = suppressMigratedLegacyItems(
          legacyItems: [image(id: 'img1')],
          remoteItems: const [],
          kind: LegacyMediaKind.image,
          legacyIdOf: (n) => n.id,
        );

        expect(result, hasLength(1));
      },
    );

    test(
      'unrelated backend media (a different legacySource) does not suppress a Hive item',
      () {
        final result = suppressMigratedLegacyItems(
          legacyItems: [image(id: 'img1')],
          remoteItems: [remoteAsset(legacySource: 'image:some-other-id')],
          kind: LegacyMediaKind.image,
          legacyIdOf: (n) => n.id,
        );

        expect(result, hasLength(1));
      },
    );

    test(
      'a normal (non-legacy) backend upload — legacySource null — does not suppress a Hive item',
      () {
        final result = suppressMigratedLegacyItems(
          legacyItems: [image(id: 'img1')],
          remoteItems: [remoteAsset(legacySource: null)],
          kind: LegacyMediaKind.image,
          legacyIdOf: (n) => n.id,
        );

        expect(result, hasLength(1));
      },
    );

    test(
      'a mismatched legacySource (wrong prefix/id) does not suppress a Hive item',
      () {
        final result = suppressMigratedLegacyItems(
          legacyItems: [image(id: 'img1')],
          // Same textual id, wrong kind prefix — must not match image:img1.
          remoteItems: [remoteAsset(legacySource: 'voice:img1')],
          kind: LegacyMediaKind.image,
          legacyIdOf: (n) => n.id,
        );

        expect(result, hasLength(1));
      },
    );

    test(
      'an empty backend id does not suppress a Hive item, even with a matching legacySource',
      () {
        final result = suppressMigratedLegacyItems(
          legacyItems: [image(id: 'img1')],
          remoteItems: [remoteAsset(id: '', legacySource: 'image:img1')],
          kind: LegacyMediaKind.image,
          legacyIdOf: (n) => n.id,
        );

        expect(result, hasLength(1));
      },
    );

    test(
      'matching is never by title, filename, date, or position — only by exact legacySource',
      () {
        // Same title/date/position as a genuinely different legacy item —
        // must not be treated as a match.
        final decoy = image(
          id: 'completely-different-id',
          title: 'A',
          path: '/a.png',
        );
        final result = suppressMigratedLegacyItems(
          legacyItems: [decoy],
          remoteItems: [
            remoteAsset(legacySource: 'image:img1'),
          ], // matches a DIFFERENT id
          kind: LegacyMediaKind.image,
          legacyIdOf: (n) => n.id,
        );

        expect(result, hasLength(1));
        expect(result.single, same(decoy));
      },
    );
  });

  group('multiple items', () {
    test('several migrated items are all reconciled correctly in one call', () {
      final result = suppressMigratedLegacyItems(
        legacyItems: [
          image(id: 'a'),
          image(id: 'b'),
          image(id: 'c'),
        ],
        remoteItems: [
          remoteAsset(legacySource: 'image:a'),
          remoteAsset(legacySource: 'image:c'),
        ],
        kind: LegacyMediaKind.image,
        legacyIdOf: (n) => n.id,
      );

      expect(result.map((n) => n.id), ['b']); // only the unmigrated one remains
    });
  });

  group('Hive/local-file safety', () {
    test('suppressing an item never mutates or deletes its Hive record', () {
      final note = image(id: 'img1', title: 'Keepsake');

      suppressMigratedLegacyItems(
        legacyItems: [note],
        remoteItems: [remoteAsset(legacySource: 'image:img1')],
        kind: LegacyMediaKind.image,
        legacyIdOf: (n) => n.id,
      );

      // A bare note, never added to a Hive box: calling `.save()`/
      // `.delete()` on it would throw synchronously. The fact that this
      // call above completed without throwing, and every field below is
      // unchanged, is direct evidence nothing in the reconciliation path
      // touched the Hive record at all — it only ever decided whether to
      // include the object in a returned list.
      expect(note.title, 'Keepsake');
      expect(note.id, 'img1');
      expect(note.isInBox, isFalse);
    });

    test(
      'suppressing an item never touches or deletes its local file path',
      () {
        final note = image(id: 'img1', path: '/local/original.png');

        final result = suppressMigratedLegacyItems(
          legacyItems: [note],
          remoteItems: [remoteAsset(legacySource: 'image:img1')],
          kind: LegacyMediaKind.image,
          legacyIdOf: (n) => n.id,
        );

        // Suppressed from the UI list, but the note object — and the path
        // it points at — is untouched; nothing in this module ever imports
        // dart:io or reads/deletes a file.
        expect(result, isEmpty);
        expect(note.path, '/local/original.png');
      },
    );
  });

  group(
    'mixed lists: migrated legacy + unmigrated legacy + newly-created backend items',
    () {
      test('every item appears exactly once', () {
        // Mirrors the real vault.dart/viewall_images.dart merge shape:
        // remote items (which include both migrated legacy uploads AND
        // brand-new PHASE14F-style uploads) concatenated with whichever
        // legacy items survive reconciliation.
        final legacyItems = [
          image(
            id: 'migrated-1',
          ), // has a valid backend counterpart -> suppressed
          image(id: 'still-legacy-1'), // no backend counterpart -> stays
          image(id: 'still-legacy-2'), // no backend counterpart -> stays
        ];
        final remoteItems = [
          remoteAsset(
            id: 'r1',
            legacySource: 'image:migrated-1',
          ), // the migrated one
          remoteAsset(
            id: 'r2',
            legacySource: null,
          ), // a brand-new, non-legacy upload
        ];

        final survivingLegacy = suppressMigratedLegacyItems(
          legacyItems: legacyItems,
          remoteItems: remoteItems,
          kind: LegacyMediaKind.image,
          legacyIdOf: (n) => n.id,
        );

        // Simulate the actual merge every listing site performs.
        final displayedIds = <String>[
          ...remoteItems.map((m) => m.id), // r1, r2
          ...survivingLegacy.map((n) => n.id), // still-legacy-1, still-legacy-2
        ];

        expect(displayedIds.toSet(), {
          'r1',
          'r2',
          'still-legacy-1',
          'still-legacy-2',
        });
        expect(displayedIds, hasLength(4)); // no duplicates, no drops
        expect(
          displayedIds.contains('migrated-1'),
          isFalse,
        ); // the legacy copy never shows
      });
    },
  );

  group('independence across media types', () {
    test(
      'an image legacySource never suppresses a voice or video item with the same hive id',
      () {
        final sameId = 'shared-id-123';
        final voiceResult = suppressMigratedLegacyItems(
          legacyItems: [voice(id: sameId)],
          remoteItems: [
            remoteAsset(mediaType: 'image', legacySource: 'image:$sameId'),
          ],
          kind: LegacyMediaKind.voice,
          legacyIdOf: (n) => n.id,
        );
        final videoResult = suppressMigratedLegacyItems(
          legacyItems: [video(id: sameId)],
          remoteItems: [
            remoteAsset(mediaType: 'image', legacySource: 'image:$sameId'),
          ],
          kind: LegacyMediaKind.video,
          legacyIdOf: (n) => n.id,
        );

        expect(voiceResult, hasLength(1));
        expect(videoResult, hasLength(1));
      },
    );
  });
}
