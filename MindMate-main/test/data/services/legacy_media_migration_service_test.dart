import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/core/network/api_exception.dart';
import 'package:mindmate/data/models/media/media_asset_model.dart';
import 'package:mindmate/data/repositories/media_repository.dart';
import 'package:mindmate/data/services/legacy_media_migration_service.dart';
import 'package:mindmate/image_note.dart';
import 'package:mindmate/vault.dart' show VoiceNote;
import 'package:mindmate/video_note.dart';
import 'package:mocktail/mocktail.dart';

class MockMediaRepository extends Mock implements MediaRepository {}

MediaAssetModel _asset({
  String id = 'server-id',
  String mediaType = 'image',
  String? title,
  String? legacySource,
  int? durationSeconds,
}) => MediaAssetModel(
  id: id,
  mediaType: mediaType,
  title: title,
  contentType: 'image/png',
  fileSize: 5,
  durationSeconds: durationSeconds,
  createdAt: DateTime.utc(2025, 1, 1),
  legacySource: legacySource,
);

MediaAssetPage _emptyPage() =>
    const MediaAssetPage(items: [], total: 0, limit: 1, offset: 0);

MediaAssetPage _pageWith(MediaAssetModel asset) =>
    MediaAssetPage(items: [asset], total: 1, limit: 1, offset: 0);

/// Builds a service with every Hive/filesystem dependency injected as a
/// fake — never touches a real Hive box or the real filesystem, exactly
/// like `MediaRepository`'s own tests never touch a real HTTP server.
LegacyMediaMigrationService _service(
  MockMediaRepository mediaRepository, {
  List<ImageNote> images = const [],
  List<VoiceNote> voices = const [],
  List<VideoNote> videos = const [],
  Set<String> existingFiles = const {},
  List<int> fileBytes = const [1, 2, 3],
}) => LegacyMediaMigrationService(
  mediaRepository: mediaRepository,
  imageNotesProvider: () => images,
  voiceNotesProvider: () => voices,
  videoNotesProvider: () => videos,
  fileExists: (path) async => existingFiles.contains(path),
  readFileBytes: (path) async => fileBytes,
);

ImageNote _imageNote({
  String id = 'img1',
  String path = '/local/a.png',
  String title = 'A',
  DateTime? date,
}) => ImageNote(
  id: id,
  path: path,
  title: title,
  date: date ?? DateTime(2019, 5, 1),
);

VoiceNote _voiceNote({
  String id = 'voice1',
  String localPath = '/local/a.m4a',
  String title = 'V',
  DateTime? date,
}) => VoiceNote(
  id: id,
  title: title,
  url: 'https://firebase.example/old.m4a',
  localPath: localPath,
  date: date ?? DateTime(2019, 5, 1),
  duration: const Duration(seconds: 12),
);

VideoNote _videoNote({
  String id = 'vid1',
  String path = '/local/a.mp4',
  String title = 'Vid',
  DateTime? date,
}) => VideoNote(
  id: id,
  path: path,
  title: title,
  date: date ?? DateTime(2019, 5, 1),
);

void main() {
  late MockMediaRepository mediaRepository;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mediaRepository = MockMediaRepository();
  });

  group('duplicate-safe / server-derived behavior', () {
    test(
      'an item already migrated is reported as alreadyMigrated and never uploaded',
      () async {
        final existing = _asset(id: 'existing', legacySource: 'image:img1');
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _pageWith(existing));

        final service = _service(
          mediaRepository,
          images: [_imageNote()],
          existingFiles: {'/local/a.png'},
        );
        final summary = await service.run();

        expect(summary.results, hasLength(1));
        expect(
          summary.results.single.outcome,
          LegacyMigrationOutcome.alreadyMigrated,
        );
        expect(summary.results.single.asset, existing);
        verifyNever(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        );
      },
    );

    test('checks legacy_source BEFORE ever reading the local file', () async {
      when(
        () => mediaRepository.list(
          legacySource: any(named: 'legacySource'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => _pageWith(_asset(legacySource: 'image:img1')));

      var fileExistsCalled = false;
      final service = LegacyMediaMigrationService(
        mediaRepository: mediaRepository,
        imageNotesProvider: () => [_imageNote()],
        voiceNotesProvider: () => [],
        videoNotesProvider: () => [],
        fileExists: (path) async {
          fileExistsCalled = true;
          return true;
        },
        readFileBytes: (path) async => [1],
      );

      await service.run();

      expect(fileExistsCalled, isFalse);
    });

    test(
      'a not-yet-migrated item is uploaded with the correct legacy_source and legacy_created_at',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _emptyPage());
        when(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        ).thenAnswer(
          (_) async => _asset(id: 'new-id', legacySource: 'image:img1'),
        );
        when(
          () => mediaRepository.rename(
            mediaId: any(named: 'mediaId'),
            title: any(named: 'title'),
          ),
        ).thenAnswer(
          (_) async =>
              _asset(id: 'new-id', title: 'A', legacySource: 'image:img1'),
        );

        final date = DateTime(2019, 5, 1, 10, 0);
        final service = _service(
          mediaRepository,
          images: [_imageNote(date: date)],
          existingFiles: {'/local/a.png'},
        );

        final summary = await service.run();

        expect(summary.results.single.outcome, LegacyMigrationOutcome.migrated);
        final captured = verify(
          () => mediaRepository.upload(
            fileBytes: captureAny(named: 'fileBytes'),
            filename: captureAny(named: 'filename'),
            contentType: captureAny(named: 'contentType'),
            durationSeconds: captureAny(named: 'durationSeconds'),
            legacySource: captureAny(named: 'legacySource'),
            legacyCreatedAt: captureAny(named: 'legacyCreatedAt'),
          ),
        ).captured;
        expect(captured[1], 'a.png'); // filename — basename of the local path
        expect(captured[2], 'image/png'); // contentType
        expect(captured[4], 'image:img1'); // legacySource
        expect(
          captured[5],
          date,
        ); // legacyCreatedAt — the raw local Hive DateTime
      },
    );

    test(
      'renames the newly-created asset to the legacy item\'s own title',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _emptyPage());
        when(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        ).thenAnswer(
          (_) async => _asset(id: 'new-id', legacySource: 'image:img1'),
        );
        when(
          () => mediaRepository.rename(
            mediaId: any(named: 'mediaId'),
            title: any(named: 'title'),
          ),
        ).thenAnswer(
          (_) async => _asset(
            id: 'new-id',
            title: 'My holiday photo',
            legacySource: 'image:img1',
          ),
        );

        final service = _service(
          mediaRepository,
          images: [_imageNote(title: 'My holiday photo')],
          existingFiles: {'/local/a.png'},
        );
        final summary = await service.run();

        verify(
          () => mediaRepository.rename(
            mediaId: 'new-id',
            title: 'My holiday photo',
          ),
        ).called(1);
        expect(summary.results.single.asset?.title, 'My holiday photo');
      },
    );

    test(
      'a failed rename does not fail the item — it is still reported as migrated',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _emptyPage());
        when(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        ).thenAnswer(
          (_) async => _asset(id: 'new-id', legacySource: 'image:img1'),
        );
        when(
          () => mediaRepository.rename(
            mediaId: any(named: 'mediaId'),
            title: any(named: 'title'),
          ),
        ).thenThrow(
          const ServerException(
            'The server is temporarily unavailable.',
            statusCode: 502,
          ),
        );

        final service = _service(
          mediaRepository,
          images: [_imageNote()],
          existingFiles: {'/local/a.png'},
        );
        final summary = await service.run();

        expect(summary.results.single.outcome, LegacyMigrationOutcome.migrated);
        expect(summary.results.single.asset?.id, 'new-id');
        // The rename failure must not cause a second upload attempt for
        // this item — the file is already durably on the server under its
        // legacy_source, so retrying the upload would be both pointless
        // and exactly what the duplicate-safe contract exists to avoid.
        verify(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        ).called(1);
      },
    );
  });

  group('already-migrated for each type', () {
    test(
      'an already-migrated voice note is reported alreadyMigrated and never uploaded',
      () async {
        final existing = _asset(
          id: 'existing-voice',
          mediaType: 'voice',
          legacySource: 'voice:voice1',
        );
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _pageWith(existing));

        final service = _service(
          mediaRepository,
          voices: [_voiceNote(id: 'voice1')],
        );
        final summary = await service.run();

        expect(
          summary.results.single.outcome,
          LegacyMigrationOutcome.alreadyMigrated,
        );
        expect(summary.results.single.asset, existing);
        verifyNever(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        );
      },
    );

    test(
      'an already-migrated video is reported alreadyMigrated and never uploaded',
      () async {
        final existing = _asset(
          id: 'existing-video',
          mediaType: 'video',
          legacySource: 'video:vid1',
        );
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _pageWith(existing));

        final service = _service(
          mediaRepository,
          videos: [_videoNote(id: 'vid1')],
        );
        final summary = await service.run();

        expect(
          summary.results.single.outcome,
          LegacyMigrationOutcome.alreadyMigrated,
        );
        expect(summary.results.single.asset, existing);
        verifyNever(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        );
      },
    );
  });

  group('response-loss / retry behavior', () {
    test(
      'calling run() a second time (simulating a client that lost the first response) '
      'resolves to alreadyMigrated and never uploads again',
      () async {
        // First call: nothing exists yet server-side; the upload "succeeds"
        // but — per the scenario this models — the client never got to act
        // on that response (e.g. the app was killed right after).
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _emptyPage());
        when(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        ).thenAnswer(
          (_) async => _asset(id: 'new-id', legacySource: 'image:img1'),
        );
        when(
          () => mediaRepository.rename(
            mediaId: any(named: 'mediaId'),
            title: any(named: 'title'),
          ),
        ).thenAnswer(
          (_) async => _asset(id: 'new-id', legacySource: 'image:img1'),
        );

        final service = _service(
          mediaRepository,
          images: [_imageNote(id: 'img1')],
          existingFiles: {'/local/a.png'},
        );

        final firstRun = await service.run();
        expect(
          firstRun.results.single.outcome,
          LegacyMigrationOutcome.migrated,
        );

        // The "retry": now the server DOES know about it (as it truly
        // would, since the first upload really did succeed) — the client
        // just re-runs the whole migration, exactly as if it never saw the
        // first response.
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer(
          (_) async =>
              _pageWith(_asset(id: 'new-id', legacySource: 'image:img1')),
        );

        final secondRun = await service.run();

        expect(
          secondRun.results.single.outcome,
          LegacyMigrationOutcome.alreadyMigrated,
        );
        verify(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        ).called(1); // only the first run ever uploaded
      },
    );
  });

  group('infrastructure-level failures (recorded per-item; the run continues)', () {
    test(
      'a network failure on upload is recorded as failed, not retried, not thrown',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _emptyPage());
        when(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        ).thenThrow(const NetworkException('Could not reach the server.'));

        final service = _service(
          mediaRepository,
          images: [_imageNote()],
          existingFiles: {'/local/a.png'},
        );
        final summary = await service.run();

        expect(summary.results.single.outcome, LegacyMigrationOutcome.failed);
        expect(summary.results.single.error, isA<NetworkException>());
      },
    );

    test('a 5xx failure on upload is recorded as failed', () async {
      when(
        () => mediaRepository.list(
          legacySource: any(named: 'legacySource'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => _emptyPage());
      when(
        () => mediaRepository.upload(
          fileBytes: any(named: 'fileBytes'),
          filename: any(named: 'filename'),
          contentType: any(named: 'contentType'),
          durationSeconds: any(named: 'durationSeconds'),
          legacySource: any(named: 'legacySource'),
          legacyCreatedAt: any(named: 'legacyCreatedAt'),
        ),
      ).thenThrow(
        const ServerException(
          'The server is temporarily unavailable.',
          statusCode: 502,
        ),
      );

      final service = _service(
        mediaRepository,
        images: [_imageNote()],
        existingFiles: {'/local/a.png'},
      );
      final summary = await service.run();

      expect(summary.results.single.outcome, LegacyMigrationOutcome.failed);
      expect(summary.results.single.error, isA<ServerException>());
    });

    test(
      'an auth failure on the duplicate-check is recorded as failed',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenThrow(
          const UnauthorizedException(
            'Your session has expired. Please log in again.',
            statusCode: 401,
          ),
        );

        final service = _service(mediaRepository, images: [_imageNote()]);
        final summary = await service.run();

        expect(summary.results.single.outcome, LegacyMigrationOutcome.failed);
        expect(summary.results.single.error, isA<UnauthorizedException>());
      },
    );

    test(
      'a failure on one item never stops the run: later items in the SAME kind, and later kinds, are still attempted',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _emptyPage());
        when(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        ).thenThrow(const NetworkException('Could not reach the server.'));

        final service = _service(
          mediaRepository,
          images: [_imageNote(id: 'img1', path: '/a.png')],
          voices: [_voiceNote(id: 'voice1', localPath: '/b.m4a')],
          existingFiles: {'/a.png', '/b.m4a'},
        );
        final summary = await service.run();

        // Both items were attempted despite the first one's network
        // failure — a per-item failure never pauses the batch.
        expect(summary.results, hasLength(2));
        expect(summary.results.map((r) => r.legacySource), [
          'image:img1',
          'voice:voice1',
        ]);
        expect(summary.failedCount, 2);
      },
    );
  });

  group('partial migration', () {
    test(
      'a mixed run reports each item\'s own outcome without one affecting another',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((invocation) async {
          final legacySource =
              invocation.namedArguments[#legacySource] as String;
          if (legacySource == 'image:already') {
            return _pageWith(_asset(legacySource: legacySource));
          }
          return _emptyPage();
        });
        when(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        ).thenAnswer(
          (invocation) async => _asset(
            id: 'new-id',
            legacySource: invocation.namedArguments[#legacySource] as String,
          ),
        );
        when(
          () => mediaRepository.rename(
            mediaId: any(named: 'mediaId'),
            title: any(named: 'title'),
          ),
        ).thenThrow(
          const NetworkException('Could not reach the server.'),
        ); // ignored by design

        final service = _service(
          mediaRepository,
          images: [
            _imageNote(id: 'already', path: '/already.png'), // alreadyMigrated
            _imageNote(id: 'new', path: '/new.png'), // migrated
            _imageNote(id: 'gone', path: '/gone.png'), // skippedFileMissing
            _imageNote(
              id: 'bad-ext',
              path: '/bad.bmp',
            ), // skippedUnsupportedType
          ],
          existingFiles: {
            '/already.png',
            '/new.png',
            '/bad.bmp',
          }, // '/gone.png' absent
        );

        final summary = await service.run();

        expect(summary.results, hasLength(4));
        expect(summary.alreadyMigratedCount, 1);
        expect(summary.migratedCount, 1);
        expect(summary.skippedCount, 2);
        expect(summary.cancelled, isFalse);
      },
    );
  });

  group('Hive safety', () {
    test(
      'migrating never mutates or deletes the underlying Hive record',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _emptyPage());
        when(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        ).thenAnswer(
          (_) async => _asset(id: 'new-id', legacySource: 'image:img1'),
        );
        when(
          () => mediaRepository.rename(
            mediaId: any(named: 'mediaId'),
            title: any(named: 'title'),
          ),
        ).thenAnswer(
          (_) async => _asset(
            id: 'new-id',
            legacySource: 'image:img1',
            title: 'Keepsake',
          ),
        );

        // A bare note, deliberately never added to a Hive box: if the
        // service ever called `.save()` or `.delete()` on it (both of which
        // require the object to be a live box member), that call would throw
        // synchronously and this test would fail — the fact that it doesn't
        // is itself evidence no such call was made.
        final note = _imageNote(id: 'img1', title: 'Keepsake');
        final service = _service(
          mediaRepository,
          images: [note],
          existingFiles: {'/local/a.png'},
        );

        final summary = await service.run();

        expect(summary.results.single.outcome, LegacyMigrationOutcome.migrated);
        expect(
          note.title,
          'Keepsake',
        ); // untouched — the rename only ever targets the backend row
        expect(
          note.isInBox,
          isFalse,
        ); // never added to (or removed from) a box by this service
      },
    );
  });

  group('success contract (PHASE14I-C.1)', () {
    test(
      'alreadyMigrated is refused (reported failed) when the resolved asset has a mismatched legacy_source',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
          // Wrong legacySource on the returned row — a malformed/buggy
          // response this class must not trust.
        ).thenAnswer(
          (_) async => _pageWith(_asset(legacySource: 'image:someone-else')),
        );

        final service = _service(
          mediaRepository,
          images: [_imageNote(id: 'img1')],
        );
        final summary = await service.run();

        expect(summary.results.single.outcome, LegacyMigrationOutcome.failed);
        expect(summary.results.single.error, isA<StateError>());
        expect(summary.results.single.asset, isNull);
      },
    );

    test(
      'alreadyMigrated is refused (reported failed) when the resolved asset has an empty id',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer(
          (_) async => _pageWith(_asset(id: '', legacySource: 'image:img1')),
        );

        final service = _service(
          mediaRepository,
          images: [_imageNote(id: 'img1')],
        );
        final summary = await service.run();

        expect(summary.results.single.outcome, LegacyMigrationOutcome.failed);
      },
    );

    test(
      'migrated is refused (reported failed) when the upload response has a mismatched legacy_source, and rename is never attempted',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _emptyPage());
        when(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
          // Response claims a different legacy_source than the one this
          // item actually sent.
        ).thenAnswer(
          (_) async => _asset(id: 'new-id', legacySource: 'image:wrong'),
        );

        final service = _service(
          mediaRepository,
          images: [_imageNote(id: 'img1')],
          existingFiles: {'/local/a.png'},
        );
        final summary = await service.run();

        expect(summary.results.single.outcome, LegacyMigrationOutcome.failed);
        expect(summary.results.single.error, isA<StateError>());
        verifyNever(
          () => mediaRepository.rename(
            mediaId: any(named: 'mediaId'),
            title: any(named: 'title'),
          ),
        );
      },
    );

    test(
      'migrated is refused (reported failed) when the upload response has an empty id',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _emptyPage());
        when(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        ).thenAnswer((_) async => _asset(id: '', legacySource: 'image:img1'));

        final service = _service(
          mediaRepository,
          images: [_imageNote(id: 'img1')],
          existingFiles: {'/local/a.png'},
        );
        final summary = await service.run();

        expect(summary.results.single.outcome, LegacyMigrationOutcome.failed);
        verifyNever(
          () => mediaRepository.rename(
            mediaId: any(named: 'mediaId'),
            title: any(named: 'title'),
          ),
        );
      },
    );
  });

  group('per-type migration success', () {
    test(
      'voice: migrates with correct legacy_source, content type, filename, duration, and title',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _emptyPage());
        when(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        ).thenAnswer(
          (_) async => _asset(
            id: 'new-voice-id',
            mediaType: 'voice',
            legacySource: 'voice:voice1',
            durationSeconds: 12,
          ),
        );
        when(
          () => mediaRepository.rename(
            mediaId: any(named: 'mediaId'),
            title: any(named: 'title'),
          ),
        ).thenAnswer(
          (_) async => _asset(
            id: 'new-voice-id',
            mediaType: 'voice',
            legacySource: 'voice:voice1',
            title: 'My recording',
            durationSeconds: 12,
          ),
        );

        final service = _service(
          mediaRepository,
          voices: [
            _voiceNote(
              id: 'voice1',
              localPath: '/local/a.m4a',
              title: 'My recording',
            ),
          ],
          existingFiles: {'/local/a.m4a'},
        );
        final summary = await service.run();

        expect(summary.results.single.outcome, LegacyMigrationOutcome.migrated);
        final captured = verify(
          () => mediaRepository.upload(
            fileBytes: captureAny(named: 'fileBytes'),
            filename: captureAny(named: 'filename'),
            contentType: captureAny(named: 'contentType'),
            durationSeconds: captureAny(named: 'durationSeconds'),
            legacySource: captureAny(named: 'legacySource'),
            legacyCreatedAt: captureAny(named: 'legacyCreatedAt'),
          ),
        ).captured;
        expect(captured[1], 'a.m4a'); // filename
        expect(
          captured[2],
          'audio/mp4',
        ); // contentType, from the .m4a extension
        expect(
          captured[3],
          12,
        ); // durationSeconds — VoiceNote.duration preserved
        expect(captured[4], 'voice:voice1'); // legacySource
        verify(
          () => mediaRepository.rename(
            mediaId: 'new-voice-id',
            title: 'My recording',
          ),
        ).called(1);
        expect(summary.results.single.asset?.title, 'My recording');
      },
    );

    test(
      'video: migrates with correct legacy_source, content type, filename, and title (no duration sent)',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _emptyPage());
        when(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        ).thenAnswer(
          (_) async => _asset(
            id: 'new-video-id',
            mediaType: 'video',
            legacySource: 'video:vid1',
          ),
        );
        when(
          () => mediaRepository.rename(
            mediaId: any(named: 'mediaId'),
            title: any(named: 'title'),
          ),
        ).thenAnswer(
          (_) async => _asset(
            id: 'new-video-id',
            mediaType: 'video',
            legacySource: 'video:vid1',
            title: 'Beach clip',
          ),
        );

        final service = _service(
          mediaRepository,
          videos: [
            _videoNote(id: 'vid1', path: '/local/a.mp4', title: 'Beach clip'),
          ],
          existingFiles: {'/local/a.mp4'},
        );
        final summary = await service.run();

        expect(summary.results.single.outcome, LegacyMigrationOutcome.migrated);
        final captured = verify(
          () => mediaRepository.upload(
            fileBytes: captureAny(named: 'fileBytes'),
            filename: captureAny(named: 'filename'),
            contentType: captureAny(named: 'contentType'),
            durationSeconds: captureAny(named: 'durationSeconds'),
            legacySource: captureAny(named: 'legacySource'),
            legacyCreatedAt: captureAny(named: 'legacyCreatedAt'),
          ),
        ).captured;
        expect(captured[1], 'a.mp4');
        expect(captured[2], 'video/mp4');
        expect(captured[3], isNull); // VideoNote never carries a duration
        expect(captured[4], 'video:vid1');
        expect(summary.results.single.asset?.title, 'Beach clip');
      },
    );
  });

  group('skip conditions', () {
    test('a missing local file is skipped, never uploaded', () async {
      when(
        () => mediaRepository.list(
          legacySource: any(named: 'legacySource'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => _emptyPage());

      final service = _service(
        mediaRepository,
        images: [_imageNote()],
        existingFiles: {},
      ); // file does not exist
      final summary = await service.run();

      expect(
        summary.results.single.outcome,
        LegacyMigrationOutcome.skippedFileMissing,
      );
      verifyNever(
        () => mediaRepository.upload(
          fileBytes: any(named: 'fileBytes'),
          filename: any(named: 'filename'),
          contentType: any(named: 'contentType'),
          durationSeconds: any(named: 'durationSeconds'),
          legacySource: any(named: 'legacySource'),
          legacyCreatedAt: any(named: 'legacyCreatedAt'),
        ),
      );
    });

    test('an unsupported file extension is skipped', () async {
      when(
        () => mediaRepository.list(
          legacySource: any(named: 'legacySource'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => _emptyPage());

      final service = _service(
        mediaRepository,
        images: [_imageNote(path: '/local/a.bmp')],
        existingFiles: {'/local/a.bmp'},
      );
      final summary = await service.run();

      expect(
        summary.results.single.outcome,
        LegacyMigrationOutcome.skippedUnsupportedType,
      );
    });

    test('a missing local voice file is skipped, never uploaded', () async {
      when(
        () => mediaRepository.list(
          legacySource: any(named: 'legacySource'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => _emptyPage());

      final service = _service(
        mediaRepository,
        voices: [_voiceNote()],
        existingFiles: {},
      );
      final summary = await service.run();

      expect(
        summary.results.single.outcome,
        LegacyMigrationOutcome.skippedFileMissing,
      );
    });

    test('a missing local video file is skipped, never uploaded', () async {
      when(
        () => mediaRepository.list(
          legacySource: any(named: 'legacySource'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => _emptyPage());

      final service = _service(
        mediaRepository,
        videos: [_videoNote()],
        existingFiles: {},
      );
      final summary = await service.run();

      expect(
        summary.results.single.outcome,
        LegacyMigrationOutcome.skippedFileMissing,
      );
    });

    test('an unsupported audio extension is skipped', () async {
      when(
        () => mediaRepository.list(
          legacySource: any(named: 'legacySource'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => _emptyPage());

      final service = _service(
        mediaRepository,
        voices: [
          _voiceNote(localPath: '/local/a.wma'),
        ], // not in the backend's allow-list
        existingFiles: {'/local/a.wma'},
      );
      final summary = await service.run();

      expect(
        summary.results.single.outcome,
        LegacyMigrationOutcome.skippedUnsupportedType,
      );
    });

    test('an unsupported video extension is skipped', () async {
      when(
        () => mediaRepository.list(
          legacySource: any(named: 'legacySource'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => _emptyPage());

      final service = _service(
        mediaRepository,
        videos: [_videoNote(path: '/local/a.mov')], // only .mp4 is supported
        existingFiles: {'/local/a.mov'},
      );
      final summary = await service.run();

      expect(
        summary.results.single.outcome,
        LegacyMigrationOutcome.skippedUnsupportedType,
      );
    });

    test(
      'an unreadable-but-present file is reported as failed, never uploaded',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _emptyPage());

        final service = LegacyMediaMigrationService(
          mediaRepository: mediaRepository,
          imageNotesProvider: () => [_imageNote()],
          voiceNotesProvider: () => [],
          videoNotesProvider: () => [],
          fileExists: (path) async => true, // the file exists...
          readFileBytes: (path) async => throw const FileSystemException(
            'Permission denied',
          ), // ...but can't be read
        );

        final summary = await service.run();

        expect(summary.results.single.outcome, LegacyMigrationOutcome.failed);
        expect(summary.results.single.error, isA<FileSystemException>());
        verifyNever(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        );
      },
    );

    test('an oversized file is skipped', () async {
      when(
        () => mediaRepository.list(
          legacySource: any(named: 'legacySource'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => _emptyPage());

      final service = LegacyMediaMigrationService(
        mediaRepository: mediaRepository,
        imageNotesProvider: () => [_imageNote()],
        voiceNotesProvider: () => [],
        videoNotesProvider: () => [],
        fileExists: (path) async => true,
        readFileBytes: (path) async =>
            List<int>.filled(30 * 1024 * 1024, 0), // > 25MB
      );

      final summary = await service.run();

      expect(
        summary.results.single.outcome,
        LegacyMigrationOutcome.skippedTooLarge,
      );
    });
  });

  group('failure handling', () {
    test(
      'a failed duplicate-check is reported as failed with the ApiException attached',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenThrow(
          const ServerException(
            'The server is temporarily unavailable.',
            statusCode: 502,
          ),
        );

        final service = _service(
          mediaRepository,
          images: [_imageNote()],
          existingFiles: {'/local/a.png'},
        );
        final summary = await service.run();

        expect(summary.results.single.outcome, LegacyMigrationOutcome.failed);
        expect(summary.results.single.error, isA<ServerException>());
      },
    );

    test(
      'a failed upload is reported as failed, and one item\'s failure does not stop the rest',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _emptyPage());
        when(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        ).thenThrow(
          const ServerException(
            'The server is temporarily unavailable.',
            statusCode: 502,
          ),
        );

        final service = _service(
          mediaRepository,
          images: [
            _imageNote(id: 'img1', path: '/a.png'),
            _imageNote(id: 'img2', path: '/b.png'),
          ],
          existingFiles: {'/a.png', '/b.png'},
        );
        final summary = await service.run();

        expect(summary.results, hasLength(2));
        expect(
          summary.results.every(
            (r) => r.outcome == LegacyMigrationOutcome.failed,
          ),
          isTrue,
        );
        expect(summary.failedCount, 2);
      },
    );
  });

  group('ordering', () {
    test(
      'processes images, then voice notes, then videos, in that fixed order',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _emptyPage());
        when(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
          // Echoes back the legacySource actually sent, per the success
          // contract (PHASE14I-C.1) — a fixed response wouldn't satisfy it
          // for more than one of these three differently-sourced items.
        ).thenAnswer(
          (invocation) async => _asset(
            id: invocation.namedArguments[#legacySource] as String,
            legacySource: invocation.namedArguments[#legacySource] as String,
          ),
        );
        when(
          () => mediaRepository.rename(
            mediaId: any(named: 'mediaId'),
            title: any(named: 'title'),
          ),
        ).thenAnswer(
          (invocation) async =>
              _asset(id: invocation.namedArguments[#mediaId] as String),
        );

        final service = _service(
          mediaRepository,
          images: [_imageNote(id: 'img1', path: '/a.png')],
          voices: [_voiceNote(id: 'voice1', localPath: '/a.m4a')],
          videos: [_videoNote(id: 'vid1', path: '/a.mp4')],
          existingFiles: {'/a.png', '/a.m4a', '/a.mp4'},
        );

        final seenOrder = <String>[];
        final summary = await service.run(
          onItemResult: (r) => seenOrder.add(r.legacySource),
        );

        expect(seenOrder, ['image:img1', 'voice:voice1', 'video:vid1']);
        expect(
          summary.results.every(
            (r) => r.outcome == LegacyMigrationOutcome.migrated,
          ),
          isTrue,
        );
      },
    );
  });

  group('cancellation', () {
    test(
      'stops before the next item once isCancelled returns true, and reports cancelled: true',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _emptyPage());
        when(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        ).thenAnswer(
          (invocation) async => _asset(
            id: invocation.namedArguments[#legacySource] as String,
            legacySource: invocation.namedArguments[#legacySource] as String,
          ),
        );
        when(
          () => mediaRepository.rename(
            mediaId: any(named: 'mediaId'),
            title: any(named: 'title'),
          ),
        ).thenAnswer(
          (invocation) async =>
              _asset(id: invocation.namedArguments[#mediaId] as String),
        );

        final service = _service(
          mediaRepository,
          images: [
            _imageNote(id: 'img1', path: '/a.png'),
            _imageNote(id: 'img2', path: '/b.png'),
          ],
          voices: [_voiceNote(id: 'voice1', localPath: '/c.m4a')],
          existingFiles: {'/a.png', '/b.png', '/c.m4a'},
        );

        var processed = 0;
        final summary = await service.run(
          onItemResult: (_) => processed++,
          isCancelled: () => processed >= 1,
        );

        expect(summary.cancelled, isTrue);
        expect(
          summary.results,
          hasLength(1),
        ); // never reached img2 or the voice note
      },
    );
  });

  group('dry run', () {
    test(
      'reports pending for a not-yet-migrated item without reading the file or uploading',
      () async {
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _emptyPage());

        var fileExistsCalled = false;
        final service = LegacyMediaMigrationService(
          mediaRepository: mediaRepository,
          imageNotesProvider: () => [_imageNote()],
          voiceNotesProvider: () => [],
          videoNotesProvider: () => [],
          fileExists: (path) async {
            fileExistsCalled = true;
            return true;
          },
          readFileBytes: (path) async => [1],
        );

        final summary = await service.run(dryRun: true);

        expect(summary.results.single.outcome, LegacyMigrationOutcome.pending);
        expect(fileExistsCalled, isFalse);
        verifyNever(
          () => mediaRepository.upload(
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            durationSeconds: any(named: 'durationSeconds'),
            legacySource: any(named: 'legacySource'),
            legacyCreatedAt: any(named: 'legacyCreatedAt'),
          ),
        );
      },
    );

    test(
      'still reports alreadyMigrated for an item the server already has',
      () async {
        final existing = _asset(legacySource: 'image:img1');
        when(
          () => mediaRepository.list(
            legacySource: any(named: 'legacySource'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => _pageWith(existing));

        final service = _service(mediaRepository, images: [_imageNote()]);
        final summary = await service.run(dryRun: true);

        expect(
          summary.results.single.outcome,
          LegacyMigrationOutcome.alreadyMigrated,
        );
      },
    );
  });

  group('legacy_source format', () {
    test('is "<kind>:<hive id>" for each of the three kinds', () async {
      when(
        () => mediaRepository.list(
          legacySource: any(named: 'legacySource'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => _emptyPage());

      final service = _service(
        mediaRepository,
        images: [_imageNote(id: 'i1')],
        voices: [_voiceNote(id: 'v1')],
        videos: [_videoNote(id: 'x1')],
      );

      final summary = await service.run(dryRun: true);

      expect(summary.results.map((r) => r.legacySource), [
        'image:i1',
        'voice:v1',
        'video:x1',
      ]);
    });
  });

  group('LegacyMigrationSummary counts', () {
    test('tallies each outcome correctly', () async {
      when(
        () => mediaRepository.list(
          legacySource: any(named: 'legacySource'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((invocation) async {
        final legacySource = invocation.namedArguments[#legacySource] as String;
        if (legacySource == 'image:already') {
          return _pageWith(_asset(legacySource: legacySource));
        }
        return _emptyPage();
      });

      final service = _service(
        mediaRepository,
        images: [
          _imageNote(id: 'already', path: '/a.png'),
          _imageNote(id: 'missing', path: '/missing.png'),
        ],
        existingFiles: {'/a.png'}, // '/missing.png' does not exist
      );

      final summary = await service.run();

      expect(summary.alreadyMigratedCount, 1);
      expect(summary.skippedCount, 1);
      expect(summary.migratedCount, 0);
      expect(summary.failedCount, 0);
      expect(summary.hasFailures, isFalse);
    });
  });
}
