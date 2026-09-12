import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/core/network/api_client.dart';
import 'package:mindmate/core/network/api_endpoints.dart';
import 'package:mindmate/core/network/api_exception.dart';
import 'package:mindmate/data/repositories/auth_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../fakes/fake_token_storage.dart';

class MockApiClient extends Mock implements ApiClient {}

const _tokenJson = {
  'access_token': 'access-token-1',
  'refresh_token': 'refresh-token-1',
  'token_type': 'bearer',
  'expires_in': 900,
};

const _meJson = {
  'user': {
    'id': 'e1822158-f808-4b37-b7f8-5903f92910ef',
    'email': 'phase7@example.com',
    'is_active': true,
    'is_verified': false,
    'created_at': '2026-09-11T11:40:39',
    'last_login_at': null,
  },
  'profile': {
    'full_name': 'Phase Seven',
    'age_group': null,
    'phone': null,
    'city': null,
    'country': null,
    'profile_image_url': null,
    'onboarding_completed_at': null,
  },
};

void main() {
  late MockApiClient apiClient;
  late FakeTokenStorage tokenStorage;
  late AuthRepository repository;

  setUp(() {
    apiClient = MockApiClient();
    tokenStorage = FakeTokenStorage();
    repository = AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);
  });

  group('register', () {
    test('posts to /auth/register unauthenticated and stores the returned tokens', () async {
      when(
        () => apiClient.post(ApiEndpoints.register, requiresAuth: false, data: any(named: 'data')),
      ).thenAnswer((_) async => _tokenJson);

      final tokens = await repository.register(email: 'x@example.com', password: 'correct-horse-1', fullName: 'X');

      expect(tokens.accessToken, 'access-token-1');
      expect(tokenStorage.accessToken, 'access-token-1');
      expect(tokenStorage.refreshToken, 'refresh-token-1');
      expect(tokenStorage.saveCount, 1);
    });

    test('sends email, password, and a trimmed full_name in the request body', () async {
      when(
        () => apiClient.post(any(), requiresAuth: false, data: captureAny(named: 'data')),
      ).thenAnswer((_) async => _tokenJson);

      await repository.register(email: 'x@example.com', password: 'correct-horse-1', fullName: '  X  ');

      final sentBody =
          verify(() => apiClient.post(any(), requiresAuth: false, data: captureAny(named: 'data'))).captured.single
              as Map;
      expect(sentBody['email'], 'x@example.com');
      expect(sentBody['password'], 'correct-horse-1');
      expect(sentBody['full_name'], 'X');
    });

    test('omits full_name entirely when none is provided, matching the optional backend field', () async {
      when(
        () => apiClient.post(any(), requiresAuth: false, data: captureAny(named: 'data')),
      ).thenAnswer((_) async => _tokenJson);

      await repository.register(email: 'x@example.com', password: 'correct-horse-1');

      final sentBody =
          verify(() => apiClient.post(any(), requiresAuth: false, data: captureAny(named: 'data'))).captured.single
              as Map;
      expect(sentBody.containsKey('full_name'), isFalse);
    });

    test('a duplicate-email 409 propagates as ConflictException without storing tokens', () async {
      when(
        () => apiClient.post(any(), requiresAuth: false, data: any(named: 'data')),
      ).thenThrow(const ConflictException('An account with this email already exists', statusCode: 409));

      await expectLater(
        repository.register(email: 'dupe@example.com', password: 'correct-horse-1'),
        throwsA(isA<ConflictException>()),
      );
      expect(tokenStorage.saveCount, 0);
    });

    test('a 422 validation failure propagates as ValidationException', () async {
      when(() => apiClient.post(any(), requiresAuth: false, data: any(named: 'data'))).thenThrow(
        ValidationException('password: too short', {
          'password': ['too short'],
        }),
      );

      await expectLater(
        repository.register(email: 'x@example.com', password: 'short'),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('login', () {
    test('posts to /auth/login unauthenticated and stores the returned tokens', () async {
      when(
        () => apiClient.post(ApiEndpoints.login, requiresAuth: false, data: any(named: 'data')),
      ).thenAnswer((_) async => _tokenJson);

      await repository.login(email: 'x@example.com', password: 'correct-horse-1');

      expect(tokenStorage.accessToken, 'access-token-1');
      expect(tokenStorage.refreshToken, 'refresh-token-1');
    });

    test('an incorrect-credentials 401 propagates as UnauthorizedException without storing tokens', () async {
      when(() => apiClient.post(any(), requiresAuth: false, data: any(named: 'data'))).thenThrow(
        const UnauthorizedException('Incorrect email or password', statusCode: 401),
      );

      await expectLater(
        repository.login(email: 'x@example.com', password: 'wrong'),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(tokenStorage.saveCount, 0);
    });
  });

  group('refresh', () {
    test('does not call the server at all when there is no stored refresh token', () async {
      tokenStorage.refreshToken = null;

      final result = await repository.refresh();

      expect(result, isFalse);
      verifyNever(() => apiClient.post(any(), requiresAuth: any(named: 'requiresAuth'), data: any(named: 'data')));
    });

    test('on success, replaces the stored tokens with the rotated pair and returns true', () async {
      tokenStorage.refreshToken = 'old-refresh-token';
      when(
        () => apiClient.post(ApiEndpoints.refresh, requiresAuth: false, data: any(named: 'data')),
      ).thenAnswer((_) async => _tokenJson);

      final result = await repository.refresh();

      expect(result, isTrue);
      expect(tokenStorage.accessToken, 'access-token-1');
      expect(tokenStorage.refreshToken, 'refresh-token-1');
    });

    test('on failure, clears stored tokens and returns false', () async {
      tokenStorage.accessToken = 'stale-access';
      tokenStorage.refreshToken = 'expired-refresh-token';
      when(
        () => apiClient.post(any(), requiresAuth: false, data: any(named: 'data')),
      ).thenThrow(const UnauthorizedException('Refresh token is invalid or expired', statusCode: 401));

      final result = await repository.refresh();

      expect(result, isFalse);
      expect(tokenStorage.accessToken, isNull);
      expect(tokenStorage.refreshToken, isNull);
    });
  });

  group('logout', () {
    test('sends the stored refresh token to POST /auth/logout and clears local storage', () async {
      tokenStorage.accessToken = 'a';
      tokenStorage.refreshToken = 'r';
      when(() => apiClient.post(ApiEndpoints.logout, data: any(named: 'data'))).thenAnswer((_) async => null);

      await repository.logout();

      verify(() => apiClient.post(ApiEndpoints.logout, data: {'refresh_token': 'r'})).called(1);
      expect(tokenStorage.accessToken, isNull);
      expect(tokenStorage.refreshToken, isNull);
      expect(tokenStorage.clearCount, 1);
    });

    test('still clears local storage even if the server call fails', () async {
      tokenStorage.accessToken = 'a';
      tokenStorage.refreshToken = 'r';
      when(
        () => apiClient.post(any(), data: any(named: 'data')),
      ).thenThrow(const NetworkException('Could not reach the server.'));

      await repository.logout();

      expect(tokenStorage.clearCount, 1);
      expect(tokenStorage.accessToken, isNull);
    });

    test('does not call the server at all when there is no refresh token, but still clears storage', () async {
      tokenStorage.refreshToken = null;

      await repository.logout();

      verifyNever(() => apiClient.post(any(), data: any(named: 'data')));
      expect(tokenStorage.clearCount, 1);
    });
  });

  group('getCurrentUser', () {
    test('parses GET /auth/me into a MeResponseModel', () async {
      when(() => apiClient.get(ApiEndpoints.me)).thenAnswer((_) async => _meJson);

      final me = await repository.getCurrentUser();

      expect(me.user.email, 'phase7@example.com');
      expect(me.user.id, 'e1822158-f808-4b37-b7f8-5903f92910ef');
      expect(me.profile.fullName, 'Phase Seven');
    });

    test('propagates UnauthorizedException as-is', () async {
      when(
        () => apiClient.get(any()),
      ).thenThrow(const UnauthorizedException('Could not validate credentials', statusCode: 401));

      await expectLater(repository.getCurrentUser(), throwsA(isA<UnauthorizedException>()));
    });
  });

  group('restoreSession', () {
    test('returns null immediately, without calling the server, when no token is stored', () async {
      tokenStorage.accessToken = null;

      final result = await repository.restoreSession();

      expect(result, isNull);
      verifyNever(() => apiClient.get(any()));
    });

    test('returns the current user when the stored session is valid', () async {
      tokenStorage.accessToken = 'valid-access-token';
      when(() => apiClient.get(ApiEndpoints.me)).thenAnswer((_) async => _meJson);

      final result = await repository.restoreSession();

      expect(result, isNotNull);
      expect(result!.user.email, 'phase7@example.com');
    });

    test(
      'clears tokens and returns null when /auth/me is unauthorized '
      '(ApiClient already attempted its own transparent refresh by this point)',
      () async {
        tokenStorage.accessToken = 'expired-access-token';
        tokenStorage.refreshToken = 'also-expired-refresh-token';
        when(
          () => apiClient.get(any()),
        ).thenThrow(const UnauthorizedException('Could not validate credentials', statusCode: 401));

        final result = await repository.restoreSession();

        expect(result, isNull);
        expect(tokenStorage.accessToken, isNull);
        expect(tokenStorage.refreshToken, isNull);
      },
    );

    test('rethrows a non-auth failure (e.g. network) rather than treating it as "logged out"', () async {
      tokenStorage.accessToken = 'valid-access-token';
      tokenStorage.refreshToken = 'valid-refresh-token';
      when(() => apiClient.get(any())).thenThrow(const NetworkException('Could not reach the server.'));

      await expectLater(repository.restoreSession(), throwsA(isA<NetworkException>()));
      // Tokens must be left untouched so a later retry can succeed without
      // forcing the user through a fresh login just because of a blip.
      expect(tokenStorage.accessToken, 'valid-access-token');
    });
  });
}
