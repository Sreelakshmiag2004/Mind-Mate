import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/core/network/api_client.dart';
import 'package:mindmate/core/network/api_exception.dart';
import 'package:mindmate/data/repositories/auth_repository.dart';

import '../fakes/fake_token_storage.dart';

/// Real end-to-end verification against an ACTUAL running FastAPI
/// instance — no mocked HTTP, no fake adapter. This is the strongest
/// verification available for this phase (see PHASE7_API_INTEGRATION.md,
/// section S) and is what the backend's exact contract (status codes,
/// field names, refresh-token rotation) was verified against while writing
/// `ApiClient`/`AuthRepository`/`ApiException` in the first place.
///
/// Requires a live backend reachable at [_baseUrl] — this repo's
/// `backend/.venv` plus a throwaway SQLite DATABASE_URL is enough (no
/// Docker/Postgres/MinIO needed; see backend/tests/conftest.py for the
/// same documented trade-off the test suite itself relies on). If nothing
/// is listening there, every test in this file fails fast with a
/// [NetworkException] rather than hanging — that failure IS the "backend
/// could not be started" case Step 19 asks to document, not a bug in this
/// test file.
const _baseUrl = 'http://127.0.0.1:8000';

String _uniqueEmail() => 'phase7-live-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 32)}@example.com';

const _validPassword = 'correct-horse-1';

void main() {
  group('live backend integration (requires a running FastAPI instance — see file doc comment)', () {
    late FakeTokenStorage tokenStorage;
    late AuthRepository repository;

    setUp(() {
      tokenStorage = FakeTokenStorage();
      final apiClient = ApiClient(tokenStorage: tokenStorage, baseUrl: _baseUrl);
      repository = AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);
    });

    test('register -> login -> GET /auth/me -> logout, end to end', () async {
      final email = _uniqueEmail();

      final registerTokens = await repository.register(
        email: email,
        password: _validPassword,
        fullName: 'Phase Seven Live Test',
      );
      expect(registerTokens.accessToken, isNotEmpty);
      expect(registerTokens.refreshToken, isNotEmpty);
      expect(tokenStorage.accessToken, registerTokens.accessToken);

      final loginTokens = await repository.login(email: email, password: _validPassword);
      expect(loginTokens.accessToken, isNotEmpty);
      // Confirms the backend really does hand back a fresh token pair on
      // login, distinct from registration's — not a cached/reused one.
      expect(loginTokens.accessToken, isNot(registerTokens.accessToken));

      final me = await repository.getCurrentUser();
      expect(me.user.email, email);
      expect(me.profile.fullName, 'Phase Seven Live Test');

      await repository.logout();
      expect(tokenStorage.accessToken, isNull);

      // The logged-out refresh token must now be rejected by the live
      // server — proves logout really revoked it server-side, not just
      // cleared it locally.
      await expectLater(repository.refresh(), completion(isFalse));
    });

    test('duplicate registration is rejected with a live 409', () async {
      final email = _uniqueEmail();
      await repository.register(email: email, password: _validPassword);

      await expectLater(
        repository.register(email: email, password: _validPassword),
        throwsA(isA<ConflictException>()),
      );
    });

    test('login with the wrong password is rejected with a live 401', () async {
      final email = _uniqueEmail();
      await repository.register(email: email, password: _validPassword);

      await expectLater(
        repository.login(email: email, password: 'totally-wrong-1'),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('a real access token expiring mid-session is handled transparently end to end', () async {
      // This exercises ApiClient's actual refresh-and-retry interceptor —
      // the same code path test/core/network/api_client_test.dart exercises
      // against a fake adapter — against the real server's real JWTs and
      // real refresh-token rotation, not a script.
      final email = _uniqueEmail();
      await repository.register(email: email, password: _validPassword);

      // Simulate "the access token has expired" the same way any real
      // client eventually hits it: corrupt the stored access token so the
      // very next authenticated call gets a genuine 401 from the live
      // server, forcing ApiClient through its real refresh path.
      tokenStorage.accessToken = 'deliberately-invalid-to-force-a-real-401';

      final me = await repository.getCurrentUser();
      expect(me.user.email, email);
      // ApiClient's interceptor must have replaced the corrupted token with
      // a freshly refreshed one along the way.
      expect(tokenStorage.accessToken, isNot('deliberately-invalid-to-force-a-real-401'));
    });

    test('registering with a backend-rejected password surfaces a live 422 as ValidationException', () async {
      await expectLater(
        repository.register(email: _uniqueEmail(), password: 'short'),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
