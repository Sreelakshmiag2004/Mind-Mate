import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/data/models/media/media_asset_model.dart';
import 'package:mindmate/data/repositories/media_repository.dart';
import 'package:mindmate/data/services/legacy_media_verification_service.dart';
import 'package:mindmate/image_note.dart';
import 'package:mocktail/mocktail.dart';

/// PHASE14I-H/I. Exercises [LegacyMediaVerificationService] entirely
/// against a mocked [MediaRepository] and injected local-file closures —
/// no real Hive box or network call is ever involved (two tests below
/// deliberately touch a REAL temporary file on disk, to prove end-to-end
/// that a genuine local file survives verification untouched). The one
/// real-network concern this class has — that the JWT never reaches the
/// presigned URL — is verified separately, at the `ApiClient` layer, in
/// `test/core/network/api_client_download_test.dart`, since that
/// guarantee is structurally owned by `ApiClient.downloadBytes`, not by
/// this service.
class MockMediaRepository extends Mock implements MediaRepository {}

const _kMaxUploadBytes = 25 * 1024 * 1024; // matches the backend's own limit — see the service's own doc

List<int> _bytesOfLength(int length, {int fill = 7}) => List<int>.filled(length, fill);

String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

MediaAssetModel _asset({
  String id = 'server-id',
  String mediaType = 'image',
  String? legacySource,
  DateTime? legacyCreatedAt,
  int fileSize = 5,
  String? checksumSha256,
}) => MediaAssetModel(
  id: id,
  mediaType: mediaType,
  contentType: 'image/png',
  fileSize: fileSize,
  createdAt: DateTime.utc(2025, 1, 1),
  legacySource: legacySource,
  legacyCreatedAt: legacyCreatedAt,
  checksumSha256: checksumSha256,
);

MediaAssetModel _detail(MediaAssetModel base, {String? downloadUrl}) => MediaAssetModel(
  id: base.id,
  mediaType: base.mediaType,
  contentType: base.contentType,
  fileSize: base.fileSize,
  createdAt: base.createdAt,
  legacySource: base.legacySource,
  legacyCreatedAt: base.legacyCreatedAt,
  checksumSha256: base.checksumSha256,
  downloadUrl: downloadUrl,
  downloadUrlExpiresInSeconds: downloadUrl != null ? 900 : null,
);

MediaAssetPage _emptyPage() => const MediaAssetPage(items: [], total: 0, limit: 1, offset: 0);

MediaAssetPage _pageWith(MediaAssetModel asset) => MediaAssetPage(items: [asset], total: 1, limit: 1, offset: 0);

void main() {
  late MockMediaRepository mediaRepository;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mediaRepository = MockMediaRepository();
  });

  /// Wires a fully-consistent, VERIFIED-shaped BACKEND scenario: a
  /// matching row, a fresh detail response with a download URL, and a
  /// download that returns exactly [downloadedContent] (defaults to
  /// [content], i.e. "the backend has exactly what it claims"). The
  /// LOCAL side is wired separately, via [service]'s own `localContent`
  /// parameter, below — kept apart so a test can freely make the local
  /// file agree or disagree with the backend independently.
  void wireVerifiedScenario({
    required List<int> content,
    List<int>? downloadedContent,
    String legacySource = 'image:img1',
    String mediaType = 'image',
    String backendId = 'server-id',
    DateTime? legacyCreatedAt,
    String? checksumOverride,
    int? backendFileSizeOverride,
    String downloadUrl = 'https://storage.example.invalid/bucket/object?sig=abc',
  }) {
    final checksum = checksumOverride ?? _sha256Hex(content);
    final asset = _asset(
      id: backendId,
      mediaType: mediaType,
      legacySource: legacySource,
      legacyCreatedAt: legacyCreatedAt ?? DateTime.utc(2019, 5, 1),
      fileSize: backendFileSizeOverride ?? content.length,
      checksumSha256: checksum,
    );
    when(
      () => mediaRepository.list(legacySource: any(named: 'legacySource'), limit: any(named: 'limit'), offset: any(named: 'offset')),
    ).thenAnswer((_) async => _pageWith(asset));
    when(() => mediaRepository.get(backendId)).thenAnswer((_) async => _detail(asset, downloadUrl: downloadUrl));
    when(() => mediaRepository.downloadBytes(downloadUrl)).thenAnswer((_) async => downloadedContent ?? content);
  }

  /// Builds a service with every local-filesystem dependency injected as
  /// a fake. [localContent], when given, wires BOTH [File.length]'s
  /// stand-in (the byte count) and the streamed-read stand-in
  /// (single-chunk, for simplicity — chunked behavior itself is tested
  /// separately below) consistently from one source of truth. Either can
  /// still be overridden individually for a test that needs the two to
  /// disagree (e.g. a stat that lies about the real content) or to fail
  /// outright.
  LegacyMediaVerificationService service({
    List<int>? localContent,
    Future<int> Function(String path)? localFileLength,
    Stream<List<int>> Function(String path)? openLocalFileStream,
  }) => LegacyMediaVerificationService(
    mediaRepository: mediaRepository,
    localFileLength: localFileLength ?? (localContent != null ? (_) async => localContent.length : null),
    openLocalFileStream: openLocalFileStream ?? (localContent != null ? (_) => Stream.value(localContent) : null),
  );

  group('valid migration — one test per media type', () {
    test('a valid migrated image is VERIFIED', () async {
      final content = _bytesOfLength(1024);
      wireVerifiedScenario(content: content, legacySource: 'image:img1', mediaType: 'image');

      final result = await service(localContent: content).verify(
        kind: LegacyMediaKind.image,
        legacyId: 'img1',
        localFilePath: '/local/a.png',
      );

      expect(result.isVerified, isTrue);
      expect(result.outcome, LegacyMediaVerificationOutcome.verified);
      expect(result.backendMediaId, 'server-id');
    });

    test('a valid migrated voice note is VERIFIED', () async {
      final content = _bytesOfLength(2048);
      wireVerifiedScenario(content: content, legacySource: 'voice:voice1', mediaType: 'voice');

      final result = await service(localContent: content).verify(
        kind: LegacyMediaKind.voice,
        legacyId: 'voice1',
        localFilePath: '/local/a.m4a',
      );

      expect(result.isVerified, isTrue);
    });

    test('a valid migrated video is VERIFIED', () async {
      final content = _bytesOfLength(4096);
      wireVerifiedScenario(content: content, legacySource: 'video:vid1', mediaType: 'video');

      final result = await service(localContent: content).verify(
        kind: LegacyMediaKind.video,
        legacyId: 'vid1',
        localFilePath: '/local/a.mp4',
      );

      expect(result.isVerified, isTrue);
    });
  });

  group('per-check failures (steps 1-8, unaffected by PHASE14I-I)', () {
    test('backend asset missing → backendAssetNotFound', () async {
      when(
        () => mediaRepository.list(legacySource: any(named: 'legacySource'), limit: any(named: 'limit'), offset: any(named: 'offset')),
      ).thenAnswer((_) async => _emptyPage());

      final result = await service().verify(kind: LegacyMediaKind.image, legacyId: 'missing', localFilePath: '/a.png');

      expect(result.outcome, LegacyMediaVerificationOutcome.backendAssetNotFound);
      expect(result.isVerified, isFalse);
      expect(result.backendMediaId, isNull);
    });

    test('empty backend ID → invalidBackendId', () async {
      when(
        () => mediaRepository.list(legacySource: any(named: 'legacySource'), limit: any(named: 'limit'), offset: any(named: 'offset')),
      ).thenAnswer((_) async => _pageWith(_asset(id: '', legacySource: 'image:img1')));

      final result = await service().verify(kind: LegacyMediaKind.image, legacyId: 'img1', localFilePath: '/a.png');

      expect(result.outcome, LegacyMediaVerificationOutcome.invalidBackendId);
      expect(result.backendMediaId, isNull);
    });

    test('legacy_source mismatch → legacySourceMismatch', () async {
      when(
        () => mediaRepository.list(legacySource: any(named: 'legacySource'), limit: any(named: 'limit'), offset: any(named: 'offset')),
      ).thenAnswer((_) async => _pageWith(_asset(legacySource: 'image:someone-else')));

      final result = await service().verify(kind: LegacyMediaKind.image, legacyId: 'img1', localFilePath: '/a.png');

      expect(result.outcome, LegacyMediaVerificationOutcome.legacySourceMismatch);
      expect(result.backendMediaId, 'server-id'); // available even though verification failed
    });

    test('media_type mismatch → mediaTypeMismatch', () async {
      when(
        () => mediaRepository.list(legacySource: any(named: 'legacySource'), limit: any(named: 'limit'), offset: any(named: 'offset')),
      ).thenAnswer((_) async => _pageWith(_asset(mediaType: 'voice', legacySource: 'image:img1')));

      final result = await service().verify(kind: LegacyMediaKind.image, legacyId: 'img1', localFilePath: '/a.png');

      expect(result.outcome, LegacyMediaVerificationOutcome.mediaTypeMismatch);
    });

    test('missing legacy_created_at → missingLegacyCreatedAt', () async {
      when(
        () => mediaRepository.list(legacySource: any(named: 'legacySource'), limit: any(named: 'limit'), offset: any(named: 'offset')),
      ).thenAnswer((_) async => _pageWith(_asset(legacySource: 'image:img1', legacyCreatedAt: null)));

      final result = await service().verify(kind: LegacyMediaKind.image, legacyId: 'img1', localFilePath: '/a.png');

      expect(result.outcome, LegacyMediaVerificationOutcome.missingLegacyCreatedAt);
    });

    test('local file missing/unreadable → localFileUnreadable, and no download is ever attempted', () async {
      final content = _bytesOfLength(10);
      wireVerifiedScenario(content: content);

      final result = await service(
        localFileLength: (_) async => throw Exception('simulated: file does not exist'),
      ).verify(kind: LegacyMediaKind.image, legacyId: 'img1', localFilePath: '/missing.png');

      expect(result.outcome, LegacyMediaVerificationOutcome.localFileUnreadable);
      verifyNever(() => mediaRepository.get(any()));
      verifyNever(() => mediaRepository.downloadBytes(any()));
    });

    test('backend file_size mismatch → fileSizeMismatch, and no download is ever attempted', () async {
      final content = _bytesOfLength(100);
      wireVerifiedScenario(content: content, backendFileSizeOverride: content.length);

      final result = await service(localFileLength: (_) async => 5) // genuinely different size
          .verify(kind: LegacyMediaKind.image, legacyId: 'img1', localFilePath: '/a.png');

      expect(result.outcome, LegacyMediaVerificationOutcome.fileSizeMismatch);
      verifyNever(() => mediaRepository.downloadBytes(any()));
    });

    test('missing checksum → missingChecksum', () async {
      when(
        () => mediaRepository.list(legacySource: any(named: 'legacySource'), limit: any(named: 'limit'), offset: any(named: 'offset')),
      ).thenAnswer(
        (_) async => _pageWith(_asset(legacySource: 'image:img1', legacyCreatedAt: DateTime.utc(2020), fileSize: 5, checksumSha256: null)),
      );

      final result = await service(localFileLength: (_) async => 5).verify(
        kind: LegacyMediaKind.image,
        legacyId: 'img1',
        localFilePath: '/a.png',
      );

      expect(result.outcome, LegacyMediaVerificationOutcome.missingChecksum);
    });

    test('malformed checksum → invalidChecksum', () async {
      when(
        () => mediaRepository.list(legacySource: any(named: 'legacySource'), limit: any(named: 'limit'), offset: any(named: 'offset')),
      ).thenAnswer(
        (_) async => _pageWith(
          _asset(legacySource: 'image:img1', legacyCreatedAt: DateTime.utc(2020), fileSize: 5, checksumSha256: 'not-a-valid-sha256'),
        ),
      );

      final result = await service(localFileLength: (_) async => 5).verify(
        kind: LegacyMediaKind.image,
        legacyId: 'img1',
        localFilePath: '/a.png',
      );

      expect(result.outcome, LegacyMediaVerificationOutcome.invalidChecksum);
    });
  });

  group('PHASE14I-I: local file hashing', () {
    test('IMPORTANT TEST: same size, modified local bytes → NOT_VERIFIED (localChecksumMismatch), never downloaded', () async {
      final backendContent = _bytesOfLength(256, fill: 7);
      final localContentSameSizeDifferentBytes = _bytesOfLength(256, fill: 9); // same length, different bytes
      wireVerifiedScenario(content: backendContent);

      final result = await service(localContent: localContentSameSizeDifferentBytes).verify(
        kind: LegacyMediaKind.image,
        legacyId: 'img1',
        localFilePath: '/a.png',
      );

      expect(result.outcome, LegacyMediaVerificationOutcome.localChecksumMismatch);
      expect(result.isVerified, isFalse);
      // Proves size equality alone can never be enough: the sizes above
      // are identical, yet verification correctly still fails.
      verifyNever(() => mediaRepository.get(any()));
      verifyNever(() => mediaRepository.downloadBytes(any()));
    });

    test('ANOTHER IMPORTANT TEST: matching local and backend bytes → VERIFIED', () async {
      final content = _bytesOfLength(300);
      wireVerifiedScenario(content: content);

      final result = await service(localContent: content).verify(
        kind: LegacyMediaKind.image,
        legacyId: 'img1',
        localFilePath: '/a.png',
      );

      expect(result.outcome, LegacyMediaVerificationOutcome.verified);
      expect(result.isVerified, isTrue);
    });

    test('local checksum matches → proceeds to a real backend download', () async {
      final content = _bytesOfLength(50);
      wireVerifiedScenario(content: content);

      await service(localContent: content).verify(kind: LegacyMediaKind.image, legacyId: 'img1', localFilePath: '/a.png');

      verify(() => mediaRepository.get('server-id')).called(1);
      verify(() => mediaRepository.downloadBytes(any())).called(1);
    });

    test('local checksum mismatch → backend object is NOT downloaded (and GET detail is not even fetched)', () async {
      final backendContent = _bytesOfLength(50, fill: 1);
      final wrongLocalContent = _bytesOfLength(50, fill: 2);
      wireVerifiedScenario(content: backendContent);

      await service(localContent: wrongLocalContent).verify(kind: LegacyMediaKind.image, legacyId: 'img1', localFilePath: '/a.png');

      verifyNever(() => mediaRepository.get(any()));
      verifyNever(() => mediaRepository.downloadBytes(any()));
    });

    test('local file missing at hashing time (but size check somehow passed) → localHashFailed', () async {
      final content = _bytesOfLength(20);
      wireVerifiedScenario(content: content);

      final result = await service(
        localFileLength: (_) async => content.length, // stat succeeds
        openLocalFileStream: (_) => Stream.error(const FileSystemException('simulated read error')),
      ).verify(kind: LegacyMediaKind.image, legacyId: 'img1', localFilePath: '/a.png');

      expect(result.outcome, LegacyMediaVerificationOutcome.localHashFailed);
      verifyNever(() => mediaRepository.downloadBytes(any()));
    });

    test('empty file: an empty local file and a zero-length backend record are hashed correctly, not treated as an error', () async {
      final emptyContent = <int>[];
      wireVerifiedScenario(content: emptyContent, backendFileSizeOverride: 0);

      final result = await service(localContent: emptyContent).verify(
        kind: LegacyMediaKind.image,
        legacyId: 'img1',
        localFilePath: '/a.png',
      );

      // SHA-256 of zero bytes is a well-defined, valid digest — this
      // must not be special-cased into a spurious failure.
      expect(result.outcome, LegacyMediaVerificationOutcome.verified);
    });

    test('a large local file is hashed incrementally, chunk by chunk, not as one giant buffer', () async {
      final chunks = List.generate(10, (i) => List<int>.filled(1000, i));
      final wholeContent = chunks.expand((c) => c).toList();
      var chunksDelivered = 0;
      Stream<List<int>> instrumentedStream(String path) async* {
        for (final chunk in chunks) {
          chunksDelivered++;
          yield chunk;
        }
      }

      wireVerifiedScenario(content: wholeContent);

      final result = await service(
        localFileLength: (_) async => wholeContent.length,
        openLocalFileStream: instrumentedStream,
      ).verify(kind: LegacyMediaKind.image, legacyId: 'img1', localFilePath: '/a.png');

      expect(chunksDelivered, 10); // every chunk was genuinely pulled through the stream
      expect(result.isVerified, isTrue); // and the hash computed from them is still correct
    });
  });

  group('backend/download failures (steps 10-14) — only reached once the local hash already matched', () {
    test('presigned download failure → downloadFailed', () async {
      final content = _bytesOfLength(10);
      wireVerifiedScenario(content: content);
      when(() => mediaRepository.downloadBytes(any())).thenThrow(Exception('simulated network failure'));

      final result = await service(localContent: content).verify(
        kind: LegacyMediaKind.image,
        legacyId: 'img1',
        localFilePath: '/a.png',
      );

      expect(result.outcome, LegacyMediaVerificationOutcome.downloadFailed);
    });

    test('GET /media/{id} itself failing also → downloadFailed', () async {
      final content = _bytesOfLength(5);
      wireVerifiedScenario(content: content);
      when(() => mediaRepository.get(any())).thenThrow(Exception('simulated 404'));

      final result = await service(localContent: content).verify(
        kind: LegacyMediaKind.image,
        legacyId: 'img1',
        localFilePath: '/a.png',
      );

      expect(result.outcome, LegacyMediaVerificationOutcome.downloadFailed);
    });

    test('downloaded byte count mismatch → downloadedSizeMismatch', () async {
      final content = _bytesOfLength(100);
      wireVerifiedScenario(content: content, downloadedContent: _bytesOfLength(50)); // wrong length

      final result = await service(localContent: content).verify(
        kind: LegacyMediaKind.image,
        legacyId: 'img1',
        localFilePath: '/a.png',
      );

      expect(result.outcome, LegacyMediaVerificationOutcome.downloadedSizeMismatch);
    });

    test('backend checksum mismatch: local matches, but the DOWNLOADED bytes differ → NOT_VERIFIED (checksumMismatch)', () async {
      final content = _bytesOfLength(64, fill: 7);
      final differentButSameLength = _bytesOfLength(64, fill: 9);
      wireVerifiedScenario(content: content, downloadedContent: differentButSameLength);

      final result = await service(localContent: content).verify(
        kind: LegacyMediaKind.image,
        legacyId: 'img1',
        localFilePath: '/a.png',
      );

      expect(result.outcome, LegacyMediaVerificationOutcome.checksumMismatch);
    });

    test('downloaded backend bytes modified (one byte, same length) → NOT_VERIFIED', () async {
      final original = _bytesOfLength(200);
      final modified = List<int>.from(original)..[0] = (original[0] + 1) % 256;
      wireVerifiedScenario(content: original, downloadedContent: modified);

      final result = await service(localContent: original).verify(
        kind: LegacyMediaKind.image,
        legacyId: 'img1',
        localFilePath: '/a.png',
      );

      expect(result.isVerified, isFalse);
      expect(result.outcome, LegacyMediaVerificationOutcome.checksumMismatch);
    });

    test('both local and remote hashes match → VERIFIED', () async {
      final content = _bytesOfLength(500);
      wireVerifiedScenario(content: content);

      final result = await service(localContent: content).verify(
        kind: LegacyMediaKind.image,
        legacyId: 'img1',
        localFilePath: '/a.png',
      );

      expect(result.isVerified, isTrue);
    });
  });

  group('fail-closed guarantees', () {
    test('every documented failure returns NOT_VERIFIED rather than throwing', () async {
      when(
        () => mediaRepository.list(legacySource: any(named: 'legacySource'), limit: any(named: 'limit'), offset: any(named: 'offset')),
      ).thenThrow(Exception('simulated network failure'));

      final result = await service().verify(kind: LegacyMediaKind.image, legacyId: 'x', localFilePath: '/a.png');

      expect(result.isVerified, isFalse);
    });

    test('an unexpected exception from the repository never propagates out of verify()', () async {
      when(
        () => mediaRepository.list(legacySource: any(named: 'legacySource'), limit: any(named: 'limit'), offset: any(named: 'offset')),
      ).thenThrow(StateError('totally unexpected'));

      final result = await service().verify(kind: LegacyMediaKind.image, legacyId: 'x', localFilePath: '/a.png');

      expect(result.isVerified, isFalse);
    });
  });

  group('description is always safe to show', () {
    test('never contains a URL, token, or raw exception text', () async {
      final content = _bytesOfLength(5);
      wireVerifiedScenario(
        content: content,
        downloadUrl: 'https://storage.example.invalid/secret-bucket?X-Amz-Signature=super-secret-signature',
      );
      when(() => mediaRepository.downloadBytes(any())).thenThrow(
        Exception('leaked detail: https://storage.example.invalid/secret-bucket?X-Amz-Signature=super-secret-signature'),
      );

      final result = await service(localContent: content).verify(
        kind: LegacyMediaKind.image,
        legacyId: 'img1',
        localFilePath: '/a.png',
      );

      expect(result.outcome, LegacyMediaVerificationOutcome.downloadFailed); // confirms this actually exercises the intended path
      expect(result.description, isNot(contains('https://')));
      expect(result.description, isNot(contains('X-Amz-Signature')));
      expect(result.description, isNot(contains('secret')));
    });
  });

  group('side-effect safety', () {
    test('verification never deletes a real local file on disk, and correctly reports a genuine content mismatch', () async {
      final tempFile = await File('${Directory.systemTemp.path}/phase14ii_${DateTime.now().microsecondsSinceEpoch}.png').create();
      final localBytes = _bytesOfLength(16, fill: 7);
      await tempFile.writeAsBytes(localBytes);
      addTearDown(() async {
        if (await tempFile.exists()) await tempFile.delete();
      });

      // Uses the REAL default local-file implementations (no injected
      // closures at all) against a REAL file on disk — the backend
      // claims different bytes of the same length, so this exercises
      // the genuine, production `File.openRead()` path end-to-end and
      // must fail on content, never on size.
      wireVerifiedScenario(content: _bytesOfLength(16, fill: 9));

      final result = await service().verify(kind: LegacyMediaKind.image, legacyId: 'img1', localFilePath: tempFile.path);

      expect(result.outcome, LegacyMediaVerificationOutcome.localChecksumMismatch);
      expect(await tempFile.exists(), isTrue);
      expect(await tempFile.readAsBytes(), localBytes); // untouched, byte-for-byte
    });

    test('verification never mutates the Hive record it was given a path from', () async {
      final note = ImageNote(id: 'img1', path: '/does/not/matter/for/this/test.png', title: 'Keepsake', date: DateTime(2020, 1, 1));
      wireVerifiedScenario(content: _bytesOfLength(8));

      await service(localFileLength: (_) async => 8).verify(kind: LegacyMediaKind.image, legacyId: note.id, localFilePath: note.path);

      // A bare note, never added to a Hive box: `.save()`/`.delete()`
      // would throw synchronously if this service ever called either —
      // the fact that it doesn't, and every field below is unchanged, is
      // direct evidence the Hive record was never touched.
      expect(note.title, 'Keepsake');
      expect(note.path, '/does/not/matter/for/this/test.png');
      expect(note.isInBox, isFalse);
    });

    test('verification never calls any method that could delete/rename the local file', () async {
      // LegacyMediaVerificationService has no dependency capable of
      // deleting/moving a file at all — its only local-filesystem
      // dependencies are the injected, read-only `localFileLength`/
      // `openLocalFileStream` closures. This test documents and locks in
      // that shape: adding a delete/rename capability would require
      // deliberately widening this service's constructor — a visible,
      // reviewable change, never something that could happen silently.
      var lengthCalls = 0;
      final content = _bytesOfLength(5);
      wireVerifiedScenario(content: content);

      final result = await service(
        localFileLength: (_) async {
          lengthCalls++;
          return content.length;
        },
        openLocalFileStream: (_) => Stream.value(content),
      ).verify(kind: LegacyMediaKind.image, legacyId: 'img1', localFilePath: '/a.png');

      expect(result.isVerified, isTrue);
      expect(lengthCalls, 1); // stat'd exactly once, nothing else touched
    });

    test('verification never calls MediaRepository.delete or .rename', () async {
      final content = _bytesOfLength(5);
      wireVerifiedScenario(content: content);

      await service(localContent: content).verify(kind: LegacyMediaKind.image, legacyId: 'img1', localFilePath: '/a.png');

      verifyNever(() => mediaRepository.delete(any()));
      verifyNever(() => mediaRepository.rename(mediaId: any(named: 'mediaId'), title: any(named: 'title')));
    });
  });

  group('25MB bound sanity', () {
    test(
      'verification handles a file at the backend\'s own maximum size',
      () async {
        final content = _bytesOfLength(_kMaxUploadBytes);
        wireVerifiedScenario(content: content);

        final result = await service(localContent: content).verify(
          kind: LegacyMediaKind.image,
          legacyId: 'img1',
          localFilePath: '/a.png',
        );

        expect(result.isVerified, isTrue);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
