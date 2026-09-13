import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/core/network/api_client.dart';
import 'package:mindmate/core/network/api_exception.dart';

import '../../fakes/fake_token_storage.dart';

/// PHASE14I-H. Same `_ScriptedAdapter` shape as `api_client_test.dart`/
/// `api_client_upload_test.dart` (kept as its own file-local copy —
/// Dart privacy is per-file), attached here to [ApiClient]'s
/// `downloadDio` constructor parameter specifically, since
/// [ApiClient.downloadBytes] deliberately never goes through the
/// constructor's ordinary `dio` parameter — see that method's own doc.
class _ScriptedAdapter implements HttpClientAdapter {
  Future<ResponseBody> Function(RequestOptions options)? handler;
  RequestOptions? lastRequestOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequestOptions = options;
    return handler!(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _ScriptedAdapter downloadAdapter;
  late ApiClient apiClient;

  setUp(() {
    downloadAdapter = _ScriptedAdapter();
    final downloadDio = Dio()..httpClientAdapter = downloadAdapter;
    final tokenStorage = FakeTokenStorage()
      ..accessToken = 'stored-access-token';
    apiClient = ApiClient(
      tokenStorage: tokenStorage,
      baseUrl: 'https://api.test.invalid',
      downloadDio: downloadDio,
    );
  });

  group('downloadBytes', () {
    test(
      'IMPORTANT SECURITY TEST: never attaches the Authorization header, even with a stored token',
      () async {
        downloadAdapter.handler = (options) async =>
            ResponseBody.fromBytes([1, 2, 3], 200);

        await apiClient.downloadBytes(
          'https://storage.example.invalid/bucket/object?X-Amz-Signature=abc',
        );

        expect(
          downloadAdapter.lastRequestOptions!.headers.containsKey(
            'Authorization',
          ),
          isFalse,
        );
      },
    );

    test(
      'requests exactly the given absolute URL, not the app\'s own API base URL',
      () async {
        downloadAdapter.handler = (options) async =>
            ResponseBody.fromBytes([1], 200);

        await apiClient.downloadBytes(
          'https://storage.example.invalid/bucket/object',
        );

        expect(
          downloadAdapter.lastRequestOptions!.uri.toString(),
          'https://storage.example.invalid/bucket/object',
        );
      },
    );

    test('returns the exact downloaded bytes', () async {
      downloadAdapter.handler = (options) async =>
          ResponseBody.fromBytes([10, 20, 30, 40], 200);

      final bytes = await apiClient.downloadBytes(
        'https://storage.example.invalid/o',
      );

      expect(bytes, [10, 20, 30, 40]);
    });

    test(
      'a non-2xx status surfaces via the existing ApiException hierarchy',
      () async {
        downloadAdapter.handler = (options) async =>
            ResponseBody.fromBytes([], 404);

        await expectLater(
          apiClient.downloadBytes('https://storage.example.invalid/o'),
          throwsA(isA<ApiException>()),
        );
      },
    );

    test(
      'a connection error surfaces as NetworkException, same as every other call',
      () async {
        downloadAdapter.handler = (options) async {
          throw DioException(
            requestOptions: RequestOptions(
              path: 'https://storage.example.invalid/o',
            ),
            type: DioExceptionType.connectionError,
          );
        };

        await expectLater(
          apiClient.downloadBytes('https://storage.example.invalid/o'),
          throwsA(isA<NetworkException>()),
        );
      },
    );
  });
}
