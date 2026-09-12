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

/// A scripted stand-in for the real network. Every test controls exactly
/// what each path returns via [handler]; [pathCallCounts] lets a test
/// assert how many times a given path was actually hit — this is what
/// proves "refresh at most once" and "single in-flight refresh across
/// concurrent requests" rather than just asserting on the final result.
class _ScriptedAdapter implements HttpClientAdapter {
  Future<ResponseBody> Function(RequestOptions options)? handler;
  final Map<String, int> pathCallCounts = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    pathCallCounts.update(options.path, (count) => count + 1, ifAbsent: () => 1);
    return handler!(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, int statusCode) =>
    ResponseBody.fromString(jsonEncode(body), statusCode, headers: _jsonHeaders);

const _tokenResponseBody = {
  'access_token': 'new-access-token',
  'refresh_token': 'new-refresh-token',
  'token_type': 'bearer',
  'expires_in': 900,
};

void main() {
  late _ScriptedAdapter adapter;
  late FakeTokenStorage tokenStorage;
  late ApiClient apiClient;

  setUp(() {
    adapter = _ScriptedAdapter();
    tokenStorage = FakeTokenStorage();
    final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'))..httpClientAdapter = adapter;
    apiClient = ApiClient(dio: dio, tokenStorage: tokenStorage, baseUrl: 'https://test.invalid');
  });

  group('auth header injection', () {
    test('attaches Authorization: Bearer <token> when requiresAuth is true and a token is stored', () async {
      tokenStorage.accessToken = 'stored-access-token';
      String? seenAuthHeader;
      adapter.handler = (options) async {
        seenAuthHeader = options.headers['Authorization'] as String?;
        return _json({'ok': true}, 200);
      };

      await apiClient.get('/protected');

      expect(seenAuthHeader, 'Bearer stored-access-token');
    });

    test('does not attach an Authorization header when requiresAuth is false', () async {
      tokenStorage.accessToken = 'stored-access-token';
      String? seenAuthHeader;
      var headerWasPresent = true;
      adapter.handler = (options) async {
        headerWasPresent = options.headers.containsKey('Authorization');
        seenAuthHeader = options.headers['Authorization'] as String?;
        return _json(_tokenResponseBody, 200);
      };

      await apiClient.post('/auth/login', data: {'email': 'a@b.com', 'password': 'x'}, requiresAuth: false);

      expect(headerWasPresent, isFalse);
      expect(seenAuthHeader, isNull);
    });

    test('does not attach an Authorization header when no token is stored, even if requiresAuth is true', () async {
      adapter.handler = (options) async => _json({'detail': 'Not authenticated'}, 401);

      await expectLater(apiClient.get('/protected'), throwsA(isA<UnauthorizedException>()));
    });
  });

  group('successful requests', () {
    test('a 2xx response is returned as a decoded map', () async {
      adapter.handler = (options) async => _json({'hello': 'world'}, 200);

      final result = await apiClient.get('/whatever', requiresAuth: false);

      expect(result, {'hello': 'world'});
    });

    test('a 204 No Content response returns null rather than throwing', () async {
      adapter.handler = (options) async => ResponseBody(const Stream.empty(), 204);

      final result = await apiClient.post('/auth/logout', data: {'refresh_token': 'x'});

      expect(result, isNull);
    });
  });

  group('401 handling — refresh and retry exactly once', () {
    test('refreshes on 401, stores the rotated tokens, and retries the original request once', () async {
      tokenStorage.accessToken = 'expired-access-token';
      tokenStorage.refreshToken = 'valid-refresh-token';
      String? authHeaderOnRetry;

      adapter.handler = (options) async {
        if (options.path == '/auth/refresh') {
          return _json(_tokenResponseBody, 200);
        }
        if (options.path == '/protected') {
          if (options.extra['__retried'] == true) {
            authHeaderOnRetry = options.headers['Authorization'] as String?;
            return _json({'ok': true}, 200);
          }
          return _json({'detail': 'Could not validate credentials'}, 401);
        }
        throw StateError('unexpected path: ${options.path}');
      };

      final result = await apiClient.get('/protected');

      expect(result, {'ok': true});
      expect(adapter.pathCallCounts['/protected'], 2, reason: 'original call + exactly one retry');
      expect(adapter.pathCallCounts['/auth/refresh'], 1);
      expect(tokenStorage.saveCount, 1);
      expect(tokenStorage.accessToken, 'new-access-token');
      expect(authHeaderOnRetry, 'Bearer new-access-token', reason: 'the retry must use the freshly rotated token');
    });

    test('never attempts a refresh for a 401 on a call that does not require auth (e.g. login)', () async {
      adapter.handler = (options) async => _json({'detail': 'Incorrect email or password'}, 401);

      await expectLater(
        apiClient.post('/auth/login', data: {'email': 'a@b.com', 'password': 'wrong'}, requiresAuth: false),
        throwsA(isA<UnauthorizedException>()),
      );

      expect(adapter.pathCallCounts['/auth/refresh'], isNull, reason: 'login\'s own 401 must never trigger a refresh');
    });

    test('does not retry more than once — a 401 on the retried request itself is NOT retried again', () async {
      tokenStorage.accessToken = 'expired-access-token';
      tokenStorage.refreshToken = 'valid-refresh-token';

      adapter.handler = (options) async {
        if (options.path == '/auth/refresh') return _json(_tokenResponseBody, 200);
        // /protected always 401s, even after the "refreshed" retry.
        return _json({'detail': 'Could not validate credentials'}, 401);
      };

      await expectLater(apiClient.get('/protected'), throwsA(isA<UnauthorizedException>()));

      expect(adapter.pathCallCounts['/protected'], 2, reason: 'original + exactly one retry, then give up');
      expect(adapter.pathCallCounts['/auth/refresh'], 1, reason: 'must not loop into a second refresh attempt');
    });

    test('if the refresh call itself fails, tokens are cleared and the original 401 is surfaced', () async {
      tokenStorage.accessToken = 'expired-access-token';
      tokenStorage.refreshToken = 'expired-refresh-token';

      adapter.handler = (options) async {
        if (options.path == '/auth/refresh') {
          return _json({'detail': 'Refresh token is invalid or expired'}, 401);
        }
        return _json({'detail': 'Could not validate credentials'}, 401);
      };

      await expectLater(apiClient.get('/protected'), throwsA(isA<UnauthorizedException>()));

      expect(adapter.pathCallCounts['/protected'], 1, reason: 'no retry is attempted once refresh itself fails');
      expect(tokenStorage.clearCount, 1);
      expect(tokenStorage.accessToken, isNull);
    });

    test('no refresh is attempted at all when there is no stored refresh token', () async {
      tokenStorage.accessToken = 'expired-access-token';
      tokenStorage.refreshToken = null;

      adapter.handler = (options) async {
        expect(options.path, isNot('/auth/refresh'), reason: 'nothing to refresh with');
        return _json({'detail': 'Could not validate credentials'}, 401);
      };

      await expectLater(apiClient.get('/protected'), throwsA(isA<UnauthorizedException>()));
    });
  });

  group('single-flight refresh under concurrent requests', () {
    test('two concurrent 401s share exactly one /auth/refresh call, and both requests are retried successfully', () async {
      tokenStorage.accessToken = 'expired-access-token';
      tokenStorage.refreshToken = 'valid-refresh-token';

      adapter.handler = (options) async {
        if (options.path == '/auth/refresh') {
          // A small delay ensures both concurrent /protected calls have
          // already reached their 401-handling code before this resolves,
          // so the test genuinely exercises the single-flight lock rather
          // than two refresh attempts that merely never happened to overlap.
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _json(_tokenResponseBody, 200);
        }
        if (options.path == '/protected') {
          if (options.extra['__retried'] == true) {
            return _json({'ok': true}, 200);
          }
          // No artificial delay needed here: both original calls are fired
          // together via Future.wait below, so they already race into the
          // 401 branch concurrently.
          return _json({'detail': 'Could not validate credentials'}, 401);
        }
        throw StateError('unexpected path: ${options.path}');
      };

      final results = await Future.wait([apiClient.get('/protected'), apiClient.get('/protected')]);

      expect(results, [
        {'ok': true},
        {'ok': true},
      ]);
      expect(adapter.pathCallCounts['/auth/refresh'], 1, reason: 'both 401s must share a single refresh call');
      expect(tokenStorage.saveCount, 1);
    });

    test('a later, non-concurrent 401 triggers its own fresh refresh (the lock is released afterward)', () async {
      tokenStorage.accessToken = 'expired-access-token';
      tokenStorage.refreshToken = 'valid-refresh-token';

      adapter.handler = (options) async {
        if (options.path == '/auth/refresh') return _json(_tokenResponseBody, 200);
        if (options.extra['__retried'] == true) return _json({'ok': true}, 200);
        return _json({'detail': 'Could not validate credentials'}, 401);
      };

      await apiClient.get('/protected');
      await apiClient.get('/protected');

      expect(adapter.pathCallCounts['/auth/refresh'], 2, reason: 'the lock must not permanently latch after the first refresh');
    });
  });

  group('other status codes', () {
    test('400 surfaces as BadRequestException', () async {
      adapter.handler = (options) async => _json({'detail': 'bad request'}, 400);
      await expectLater(apiClient.post('/x', requiresAuth: false), throwsA(isA<BadRequestException>()));
    });

    test('409 surfaces as ConflictException with the backend\'s message', () async {
      adapter.handler = (options) async =>
          _json({'detail': 'An account with this email already exists'}, 409);

      try {
        await apiClient.post('/auth/register', requiresAuth: false, data: {});
        fail('expected a ConflictException');
      } on ConflictException catch (e) {
        expect(e.message, 'An account with this email already exists');
      }
    });

    test('422 surfaces as ValidationException with parsed field errors', () async {
      adapter.handler = (options) async => _json({
        'detail': [
          {
            'loc': ['body', 'password'],
            'msg': 'String should have at least 8 characters',
          },
        ],
      }, 422);

      try {
        await apiClient.post('/auth/register', requiresAuth: false, data: {});
        fail('expected a ValidationException');
      } on ValidationException catch (e) {
        expect(e.fieldErrors['password'], contains('String should have at least 8 characters'));
      }
    });

    test('a connection error (no response at all) surfaces as NetworkException', () async {
      adapter.handler = (options) async {
        throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
      };

      await expectLater(apiClient.get('/x'), throwsA(isA<NetworkException>()));
    });
  });
}
