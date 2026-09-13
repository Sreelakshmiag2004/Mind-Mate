import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/core/network/api_client.dart';
import 'package:mindmate/core/network/api_exception.dart';

import '../../fakes/fake_token_storage.dart';

const _jsonHeaders = {
  'content-type': ['application/json'],
};

/// A scripted stand-in for the real network — same shape as
/// `api_client_test.dart`'s own `_ScriptedAdapter` (kept as a separate,
/// file-local copy since that one is private to its file), extended here
/// to also capture the request's actual byte stream, so a test can
/// inspect the genuine multipart body Dio produced rather than just the
/// headers.
class _ScriptedAdapter implements HttpClientAdapter {
  Future<ResponseBody> Function(RequestOptions options)? handler;
  RequestOptions? lastRequestOptions;
  List<int>? lastRequestBodyBytes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequestOptions = options;
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      lastRequestBodyBytes = chunks.expand((chunk) => chunk).toList();
    }
    return handler!(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, int statusCode) =>
    ResponseBody.fromString(jsonEncode(body), statusCode, headers: _jsonHeaders);

void main() {
  late _ScriptedAdapter adapter;
  late ApiClient apiClient;

  setUp(() {
    adapter = _ScriptedAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'))..httpClientAdapter = adapter;
    apiClient = ApiClient(dio: dio, tokenStorage: FakeTokenStorage(), baseUrl: 'https://test.invalid');
  });

  group('uploadMultipart', () {
    test('POSTs to the given path', () async {
      adapter.handler = (options) async => _json({'id': 'x'}, 201);

      await apiClient.uploadMultipart(
        '/media/upload',
        fileBytes: [1, 2, 3],
        filename: 'a.png',
        contentType: 'image/png',
      );

      expect(adapter.lastRequestOptions!.path, '/media/upload');
      expect(adapter.lastRequestOptions!.method, 'POST');
    });

    test(
      'sends a genuine multipart/form-data request — NOT the global default application/json — '
      'with a real Dio-generated boundary',
      () async {
        adapter.handler = (options) async => _json({'id': 'x'}, 201);

        await apiClient.uploadMultipart(
          '/media/upload',
          fileBytes: [1, 2, 3],
          filename: 'a.png',
          contentType: 'image/png',
        );

        final contentTypeHeader = adapter.lastRequestOptions!.headers['content-type'] as String;
        expect(contentTypeHeader, startsWith('multipart/form-data; boundary='));
        expect(contentTypeHeader, isNot(contains('application/json')));
      },
    );

    test('the multipart body contains the file part with its filename, content type, and exact bytes', () async {
      adapter.handler = (options) async => _json({'id': 'x'}, 201);

      await apiClient.uploadMultipart(
        '/media/upload',
        fileBytes: utf8.encode('hello world'),
        filename: 'note.m4a',
        contentType: 'audio/mp4',
      );

      // dio lowercases multipart part headers (`content-disposition`/
      // `content-type`), unlike the outer request's own `Content-Type`
      // header asserted above — matched here case-for-case rather than
      // asserting a specific case that happens not to be dio's.
      final bodyText = utf8.decode(adapter.lastRequestBodyBytes!, allowMalformed: true);
      expect(bodyText, contains('name="file"'));
      expect(bodyText, contains('filename="note.m4a"'));
      expect(bodyText, contains('content-type: audio/mp4'));
      expect(bodyText, contains('hello world'));
    });

    test('includes an optional form field (duration_seconds) as a plain multipart field', () async {
      adapter.handler = (options) async => _json({'id': 'x'}, 201);

      await apiClient.uploadMultipart(
        '/media/upload',
        fileBytes: [1],
        filename: 'a.m4a',
        contentType: 'audio/mp4',
        fields: {'duration_seconds': 42},
      );

      final bodyText = utf8.decode(adapter.lastRequestBodyBytes!, allowMalformed: true);
      expect(bodyText, contains('name="duration_seconds"'));
      expect(bodyText, contains('42'));
    });

    test('omits the optional field entirely when none is given', () async {
      adapter.handler = (options) async => _json({'id': 'x'}, 201);

      await apiClient.uploadMultipart('/media/upload', fileBytes: [1], filename: 'a.png', contentType: 'image/png');

      final bodyText = utf8.decode(adapter.lastRequestBodyBytes!, allowMalformed: true);
      expect(bodyText, isNot(contains('duration_seconds')));
    });

    test('still attaches the Authorization header, exactly like every other request', () async {
      final tokenStorage = FakeTokenStorage()..accessToken = 'stored-access-token';
      final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'))..httpClientAdapter = adapter;
      final client = ApiClient(dio: dio, tokenStorage: tokenStorage, baseUrl: 'https://test.invalid');
      adapter.handler = (options) async => _json({'id': 'x'}, 201);

      await client.uploadMultipart('/media/upload', fileBytes: [1], filename: 'a.png', contentType: 'image/png');

      expect(adapter.lastRequestOptions!.headers['Authorization'], 'Bearer stored-access-token');
    });

    test('returns the parsed JSON response body', () async {
      adapter.handler = (options) async => _json({'id': 'new-id', 'media_type': 'image'}, 201);

      final result = await apiClient.uploadMultipart(
        '/media/upload',
        fileBytes: [1],
        filename: 'a.png',
        contentType: 'image/png',
      );

      expect(result, {'id': 'new-id', 'media_type': 'image'});
    });

    test('a 415 (unsupported content type) surfaces via the existing ApiException hierarchy', () async {
      adapter.handler = (options) async => _json({'detail': "Content type 'application/octet-stream' is not supported"}, 415);

      await expectLater(
        apiClient.uploadMultipart('/media/upload', fileBytes: [1], filename: 'x.exe', contentType: 'application/octet-stream'),
        throwsA(isA<ApiException>()),
      );
    });

    test('a 413 (file too large) surfaces via the existing ApiException hierarchy', () async {
      adapter.handler = (options) async => _json({'detail': 'File is too large'}, 413);

      await expectLater(
        apiClient.uploadMultipart('/media/upload', fileBytes: [1], filename: 'a.png', contentType: 'image/png'),
        throwsA(isA<ApiException>()),
      );
    });

    test('a connection error surfaces as NetworkException, same as every other call', () async {
      adapter.handler = (options) async {
        throw DioException(requestOptions: RequestOptions(path: '/media/upload'), type: DioExceptionType.connectionError);
      };

      await expectLater(
        apiClient.uploadMultipart('/media/upload', fileBytes: [1], filename: 'a.png', contentType: 'image/png'),
        throwsA(isA<NetworkException>()),
      );
    });

    test('does not alter the global JSON default for an ordinary request made afterward', () async {
      adapter.handler = (options) async => _json({'ok': true}, 200);
      await apiClient.uploadMultipart('/media/upload', fileBytes: [1], filename: 'a.png', contentType: 'image/png');

      await apiClient.get('/journals', requiresAuth: false);

      expect(adapter.lastRequestOptions!.path, '/journals');
      expect(adapter.lastRequestOptions!.headers['content-type'], 'application/json');
    });
  });
}
