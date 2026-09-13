import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/core/network/api_client.dart';
import 'package:mindmate/core/network/api_endpoints.dart';
import 'package:mindmate/core/network/api_exception.dart';
import 'package:mindmate/data/repositories/media_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

Map<String, dynamic> _assetJson({
  String id = 'a1b2c3',
  String mediaType = 'image',
  String? title,
  int? durationSeconds,
  String? downloadUrl,
}) => {
  'id': id,
  'media_type': mediaType,
  'original_filename': 'a.png',
  'title': title,
  'content_type': 'image/png',
  'file_size': 5,
  'duration_seconds': durationSeconds,
  'created_at': '2025-01-06T09:15:00+00:00',
  if (downloadUrl != null) 'download_url': downloadUrl,
  if (downloadUrl != null) 'download_url_expires_in_seconds': 900,
};

void main() {
  late MockApiClient apiClient;
  late MediaRepository repository;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    apiClient = MockApiClient();
    repository = MediaRepository(apiClient: apiClient);
  });

  group('upload', () {
    test(
      'calls ApiClient.uploadMultipart against POST /media/upload',
      () async {
        when(
          () => apiClient.uploadMultipart(
            any(),
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            fields: any(named: 'fields'),
          ),
        ).thenAnswer((_) async => _assetJson());

        await repository.upload(
          fileBytes: [1, 2, 3],
          filename: 'a.png',
          contentType: 'image/png',
        );

        verify(
          () => apiClient.uploadMultipart(
            ApiEndpoints.mediaUpload,
            fileBytes: [1, 2, 3],
            filename: 'a.png',
            contentType: 'image/png',
            fields: any(named: 'fields'),
          ),
        ).called(1);
      },
    );

    test('sends the exact bytes, filename, and content type given', () async {
      when(
        () => apiClient.uploadMultipart(
          any(),
          fileBytes: any(named: 'fileBytes'),
          filename: any(named: 'filename'),
          contentType: any(named: 'contentType'),
          fields: any(named: 'fields'),
        ),
      ).thenAnswer((_) async => _assetJson(mediaType: 'voice'));

      await repository.upload(
        fileBytes: [9, 9, 9],
        filename: 'note.m4a',
        contentType: 'audio/mp4',
      );

      final captured = verify(
        () => apiClient.uploadMultipart(
          any(),
          fileBytes: captureAny(named: 'fileBytes'),
          filename: captureAny(named: 'filename'),
          contentType: captureAny(named: 'contentType'),
          fields: any(named: 'fields'),
        ),
      ).captured;
      expect(captured[0], [9, 9, 9]);
      expect(captured[1], 'note.m4a');
      expect(captured[2], 'audio/mp4');
    });

    test('includes duration_seconds as a form field when given', () async {
      when(
        () => apiClient.uploadMultipart(
          any(),
          fileBytes: any(named: 'fileBytes'),
          filename: any(named: 'filename'),
          contentType: any(named: 'contentType'),
          fields: any(named: 'fields'),
        ),
      ).thenAnswer(
        (_) async => _assetJson(mediaType: 'voice', durationSeconds: 42),
      );

      await repository.upload(
        fileBytes: [1],
        filename: 'a.m4a',
        contentType: 'audio/mp4',
        durationSeconds: 42,
      );

      final fields =
          verify(
                () => apiClient.uploadMultipart(
                  any(),
                  fileBytes: any(named: 'fileBytes'),
                  filename: any(named: 'filename'),
                  contentType: any(named: 'contentType'),
                  fields: captureAny(named: 'fields'),
                ),
              ).captured.single
              as Map;
      expect(fields, {'duration_seconds': 42});
    });

    test(
      'omits duration_seconds entirely when not given — no user_id/uid/username/media_type/object_key either',
      () async {
        when(
          () => apiClient.uploadMultipart(
            any(),
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            fields: any(named: 'fields'),
          ),
        ).thenAnswer((_) async => _assetJson());

        await repository.upload(
          fileBytes: [1],
          filename: 'a.png',
          contentType: 'image/png',
        );

        final fields =
            verify(
                  () => apiClient.uploadMultipart(
                    any(),
                    fileBytes: any(named: 'fileBytes'),
                    filename: any(named: 'filename'),
                    contentType: any(named: 'contentType'),
                    fields: captureAny(named: 'fields'),
                  ),
                ).captured.single
                as Map;
        expect(fields, isEmpty);
        expect(fields.containsKey('user_id'), isFalse);
        expect(fields.containsKey('uid'), isFalse);
        expect(fields.containsKey('username'), isFalse);
        expect(fields.containsKey('media_type'), isFalse);
        expect(fields.containsKey('object_key'), isFalse);
      },
    );

    test('returns the parsed MediaAssetModel', () async {
      when(
        () => apiClient.uploadMultipart(
          any(),
          fileBytes: any(named: 'fileBytes'),
          filename: any(named: 'filename'),
          contentType: any(named: 'contentType'),
          fields: any(named: 'fields'),
        ),
      ).thenAnswer((_) async => _assetJson(id: 'new-id', mediaType: 'image'));

      final asset = await repository.upload(
        fileBytes: [1],
        filename: 'a.png',
        contentType: 'image/png',
      );

      expect(asset.id, 'new-id');
      expect(asset.mediaType, 'image');
    });

    for (final entry in {
      401: 401,
      413: 413,
      415: 415,
      422: 422,
      500: 500,
    }.entries) {
      test('a ${entry.key} from the backend propagates unchanged', () async {
        final Exception thrown = switch (entry.key) {
          401 => const UnauthorizedException(
            'Could not validate credentials',
            statusCode: 401,
          ),
          422 => ValidationException('file: field required', {
            'file': ['field required'],
          }),
          500 => const ServerException(
            'The server is temporarily unavailable.',
            statusCode: 500,
          ),
          _ => UnknownApiException('Unexpected', statusCode: entry.key),
        };
        when(
          () => apiClient.uploadMultipart(
            any(),
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            fields: any(named: 'fields'),
          ),
        ).thenThrow(thrown);

        await expectLater(
          repository.upload(
            fileBytes: [1],
            filename: 'a.png',
            contentType: 'image/png',
          ),
          throwsA(same(thrown)),
        );
      });
    }

    test('a network failure propagates as NetworkException', () async {
      when(
        () => apiClient.uploadMultipart(
          any(),
          fileBytes: any(named: 'fileBytes'),
          filename: any(named: 'filename'),
          contentType: any(named: 'contentType'),
          fields: any(named: 'fields'),
        ),
      ).thenThrow(const NetworkException('Could not reach the server.'));

      await expectLater(
        repository.upload(
          fileBytes: [1],
          filename: 'a.png',
          contentType: 'image/png',
        ),
        throwsA(isA<NetworkException>()),
      );
    });

    // --- PHASE14I-C: legacy Hive media migration fields ---

    test('includes legacy_source as a form field when given', () async {
      when(
        () => apiClient.uploadMultipart(
          any(),
          fileBytes: any(named: 'fileBytes'),
          filename: any(named: 'filename'),
          contentType: any(named: 'contentType'),
          fields: any(named: 'fields'),
        ),
      ).thenAnswer((_) async => _assetJson());

      await repository.upload(
        fileBytes: [1],
        filename: 'a.png',
        contentType: 'image/png',
        legacySource: 'image:abc',
      );

      final fields =
          verify(
                () => apiClient.uploadMultipart(
                  any(),
                  fileBytes: any(named: 'fileBytes'),
                  filename: any(named: 'filename'),
                  contentType: any(named: 'contentType'),
                  fields: captureAny(named: 'fields'),
                ),
              ).captured.single
              as Map;
      expect(fields, {'legacy_source': 'image:abc'});
    });

    test(
      'sends legacy_created_at as a UTC ISO-8601 string, converted from a local DateTime',
      () async {
        when(
          () => apiClient.uploadMultipart(
            any(),
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            fields: any(named: 'fields'),
          ),
        ).thenAnswer((_) async => _assetJson());

        await repository.upload(
          fileBytes: [1],
          filename: 'a.png',
          contentType: 'image/png',
          legacySource: 'image:abc',
          legacyCreatedAt: DateTime.utc(2020, 6, 15, 10, 30),
        );

        final fields =
            verify(
                  () => apiClient.uploadMultipart(
                    any(),
                    fileBytes: any(named: 'fileBytes'),
                    filename: any(named: 'filename'),
                    contentType: any(named: 'contentType'),
                    fields: captureAny(named: 'fields'),
                  ),
                ).captured.single
                as Map;
        expect(fields['legacy_created_at'], '2020-06-15T10:30:00.000Z');
      },
    );

    test(
      'omits legacy_source/legacy_created_at entirely when not given (a normal upload is unaffected)',
      () async {
        when(
          () => apiClient.uploadMultipart(
            any(),
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            fields: any(named: 'fields'),
          ),
        ).thenAnswer((_) async => _assetJson());

        await repository.upload(
          fileBytes: [1],
          filename: 'a.png',
          contentType: 'image/png',
        );

        final fields =
            verify(
                  () => apiClient.uploadMultipart(
                    any(),
                    fileBytes: any(named: 'fileBytes'),
                    filename: any(named: 'filename'),
                    contentType: any(named: 'contentType'),
                    fields: captureAny(named: 'fields'),
                  ),
                ).captured.single
                as Map;
        expect(fields.containsKey('legacy_source'), isFalse);
        expect(fields.containsKey('legacy_created_at'), isFalse);
      },
    );

    test(
      'a 422 (e.g. blank/malformed legacy_source) propagates as ValidationException',
      () async {
        when(
          () => apiClient.uploadMultipart(
            any(),
            fileBytes: any(named: 'fileBytes'),
            filename: any(named: 'filename'),
            contentType: any(named: 'contentType'),
            fields: any(named: 'fields'),
          ),
        ).thenThrow(
          ValidationException('legacy_source: must not be blank', {
            'legacy_source': ['must not be blank'],
          }),
        );

        await expectLater(
          repository.upload(
            fileBytes: [1],
            filename: 'a.png',
            contentType: 'image/png',
            legacySource: '',
          ),
          throwsA(isA<ValidationException>()),
        );
      },
    );
  });

  group('list', () {
    test('GETs /media with media_type/limit/offset query parameters', () async {
      when(
        () => apiClient.get(
          any(),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => {'items': [], 'total': 0, 'limit': 10, 'offset': 5},
      );

      await repository.list(mediaType: 'voice', limit: 10, offset: 5);

      verify(
        () => apiClient.get(
          ApiEndpoints.media,
          queryParameters: {'media_type': 'voice', 'limit': 10, 'offset': 5},
        ),
      ).called(1);
    });

    test('omits media_type from the query when not given', () async {
      when(
        () => apiClient.get(
          any(),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => {'items': [], 'total': 0, 'limit': 30, 'offset': 0},
      );

      await repository.list();

      final query =
          verify(
                () => apiClient.get(
                  any(),
                  queryParameters: captureAny(named: 'queryParameters'),
                ),
              ).captured.single
              as Map;
      expect(query.containsKey('media_type'), isFalse);
      expect(query, {'limit': 30, 'offset': 0});
    });

    test('parses the returned Page[MediaAssetRead] correctly', () async {
      when(
        () => apiClient.get(
          any(),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => {
          'items': [_assetJson(id: 'a'), _assetJson(id: 'b')],
          'total': 2,
          'limit': 30,
          'offset': 0,
        },
      );

      final page = await repository.list();

      expect(page.items, hasLength(2));
      expect(page.total, 2);
    });

    test('a 401 propagates as UnauthorizedException', () async {
      when(
        () => apiClient.get(
          any(),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenThrow(
        const UnauthorizedException(
          'Could not validate credentials',
          statusCode: 401,
        ),
      );

      await expectLater(
        repository.list(),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    // --- PHASE14I-C: legacy_source lookup filter ---

    test(
      'GETs /media with a legacy_source query parameter when given',
      () async {
        when(
          () => apiClient.get(
            any(),
            queryParameters: any(named: 'queryParameters'),
          ),
        ).thenAnswer(
          (_) async => {'items': [], 'total': 0, 'limit': 1, 'offset': 0},
        );

        await repository.list(legacySource: 'image:abc', limit: 1, offset: 0);

        verify(
          () => apiClient.get(
            ApiEndpoints.media,
            queryParameters: {
              'legacy_source': 'image:abc',
              'limit': 1,
              'offset': 0,
            },
          ),
        ).called(1);
      },
    );

    test('omits legacy_source from the query when not given', () async {
      when(
        () => apiClient.get(
          any(),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => {'items': [], 'total': 0, 'limit': 30, 'offset': 0},
      );

      await repository.list();

      final query =
          verify(
                () => apiClient.get(
                  any(),
                  queryParameters: captureAny(named: 'queryParameters'),
                ),
              ).captured.single
              as Map;
      expect(query.containsKey('legacy_source'), isFalse);
    });
  });

  group('get', () {
    test('GETs /media/{id}', () async {
      when(
        () => apiClient.get(any()),
      ).thenAnswer((_) async => _assetJson(downloadUrl: 'https://storage/x'));

      await repository.get('a1b2c3');

      verify(() => apiClient.get(ApiEndpoints.mediaById('a1b2c3'))).called(1);
    });

    test(
      'returns metadata plus download_url/download_url_expires_in_seconds',
      () async {
        when(
          () => apiClient.get(any()),
        ).thenAnswer((_) async => _assetJson(downloadUrl: 'https://storage/x'));

        final asset = await repository.get('a1b2c3');

        expect(asset.downloadUrl, 'https://storage/x');
        expect(asset.downloadUrlExpiresInSeconds, 900);
      },
    );

    test('a 404 propagates as NotFoundException', () async {
      when(
        () => apiClient.get(any()),
      ).thenThrow(const NotFoundException('Media not found', statusCode: 404));

      await expectLater(
        repository.get('missing'),
        throwsA(isA<NotFoundException>()),
      );
    });
  });

  group('rename', () {
    test('PATCHes /media/{id} with a body containing ONLY title', () async {
      when(
        () => apiClient.patch(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => _assetJson(title: 'x'));

      await repository.rename(mediaId: 'a1b2c3', title: 'Beach trip');

      final sentBody =
          verify(
                () => apiClient.patch(
                  ApiEndpoints.mediaById('a1b2c3'),
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map;
      expect(sentBody, {'title': 'Beach trip'});
    });

    test('returns the updated MediaAssetModel', () async {
      when(
        () => apiClient.patch(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => _assetJson(title: 'Renamed'));

      final asset = await repository.rename(
        mediaId: 'a1b2c3',
        title: 'Renamed',
      );

      expect(asset.title, 'Renamed');
    });

    test(
      'a 422 (e.g. blank title) propagates as ValidationException',
      () async {
        when(() => apiClient.patch(any(), data: any(named: 'data'))).thenThrow(
          ValidationException('title: field required', {
            'title': ['field required'],
          }),
        );

        await expectLater(
          repository.rename(mediaId: 'a1b2c3', title: ''),
          throwsA(isA<ValidationException>()),
        );
      },
    );

    test('a 404 propagates as NotFoundException', () async {
      when(
        () => apiClient.patch(any(), data: any(named: 'data')),
      ).thenThrow(const NotFoundException('Media not found', statusCode: 404));

      await expectLater(
        repository.rename(mediaId: 'missing', title: 'x'),
        throwsA(isA<NotFoundException>()),
      );
    });
  });

  group('delete', () {
    test('DELETEs /media/{id}', () async {
      when(() => apiClient.delete(any())).thenAnswer((_) async => null);

      await repository.delete('a1b2c3');

      verify(
        () => apiClient.delete(ApiEndpoints.mediaById('a1b2c3')),
      ).called(1);
    });

    test('a 404 propagates as NotFoundException', () async {
      when(
        () => apiClient.delete(any()),
      ).thenThrow(const NotFoundException('Media not found', statusCode: 404));

      await expectLater(
        repository.delete('missing'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('a network failure propagates as NetworkException', () async {
      when(
        () => apiClient.delete(any()),
      ).thenThrow(const NetworkException('Could not reach the server.'));

      await expectLater(
        repository.delete('a1b2c3'),
        throwsA(isA<NetworkException>()),
      );
    });

    test('a 5xx propagates as ServerException', () async {
      when(() => apiClient.delete(any())).thenThrow(
        const ServerException(
          'The server is temporarily unavailable.',
          statusCode: 502,
        ),
      );

      await expectLater(
        repository.delete('a1b2c3'),
        throwsA(isA<ServerException>()),
      );
    });
  });
}
